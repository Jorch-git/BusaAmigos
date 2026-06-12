import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../transport_service.dart';
import 'mesh_envelope.dart';
import 'mesh_profile.dart';

/// Convierte un transporte de ENLACE (que solo habla con peers conectados
/// directamente, como [NearbyTransport]) en un transporte MESH multi-hop.
///
/// Qué añade sobre el transporte base — y que tu Nearby actual NO tiene:
///   - **Store & forward**: si A y C no se ven pero ambos ven a B, el mensaje
///     de A salta por B hasta C. Así el grupo se mantiene conectado aunque la
///     topología cambie (gente que se mueve en un festival).
///   - **Dedupe**: cada mensaje lleva un id; si ya lo vimos, no lo
///     reprocesamos ni reenviamos. Esto rompe los bucles de la malla.
///   - **TTL + hop count**: el mensaje muere tras N saltos (no vive para siempre).
///   - **Gossip + jitter**: en multitudes, reenviar con probabilidad < 1 y con
///     un retardo aleatorio evita las "tormentas de broadcast" que tumban a
///     las mallas ingenuas. Esto es lo que da estabilidad real con mucha gente.
///
/// Es agnóstico del contenido: el [payload] del sobre es el blob ya cifrado
/// E2E. Esta capa solo lee la cabecera de ruteo (en claro) para decidir si
/// entrega y/o reenvía.
class MeshTransport implements TransportService {
  MeshTransport(this.link, {this.profile = MeshProfile.standard});

  /// Transporte base que mueve bytes entre peers directos.
  final TransportService link;

  MeshProfile profile;

  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();

  TransportState _state = TransportState.idle;
  String _selfId = '';
  final _random = Random();
  int _counter = 0;

  StreamSubscription? _linkStateSub;
  StreamSubscription? _linkInSub;

  /// Ids vistos -> momento en que se vieron. LinkedHashMap conserva el orden
  /// de inserción, lo que facilita expulsar los más viejos.
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();

  final List<Timer> _pendingForwards = [];

  // ---- Diagnóstico (para la consola de desarrollo) ----
  int originated = 0, delivered = 0, forwarded = 0, dropped = 0, duplicates = 0;

  Map<String, dynamic> get meshStats => {
        'profile': profile.name,
        'ttl': profile.ttl,
        'seenIds': _seen.length,
        'originated': originated,
        'delivered': delivered,
        'forwarded': forwarded,
        'droppedGossip': dropped,
        'duplicates': duplicates,
      };

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach => link.reach;

  void _setState(TransportState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    _selfId = selfId;
    _linkStateSub = link.stateStream.listen(_setState);
    _linkInSub = link.incomingStream.listen(_onLinkData);
    await link.start(groupCode: groupCode, selfId: selfId);
    _setState(link.currentState);
  }

  @override
  Future<void> send(String encryptedBlob) async {
    final id = _newId();
    _markSeen(id); // no reenviar mi propio eco si me vuelve por un vecino
    originated++;
    final env = MeshEnvelope(
      id: id,
      origin: _selfId,
      ttl: profile.ttl,
      hop: 0,
      payload: encryptedBlob,
    );
    await link.send(env.encode());
  }

  void _onLinkData(String raw) {
    final env = MeshEnvelope.tryParse(raw);
    if (env == null) {
      // No es un sobre mesh (ghost de dev, blob legacy): pásalo tal cual.
      _incomingCtrl.add(raw);
      return;
    }

    if (_isSeen(env.id)) {
      duplicates++;
      return;
    }
    _markSeen(env.id);

    // Entrega a la app solo si no lo originamos nosotros.
    if (env.origin != _selfId) {
      delivered++;
      _incomingCtrl.add(env.payload);
    }

    // Reenvío multi-hop.
    if (env.ttl > 0) _scheduleForward(env);
  }

  void _scheduleForward(MeshEnvelope env) {
    // Gossip: en multitudes no hace falta que todos reenvíen.
    if (profile.forwardProbability < 1.0 &&
        _random.nextDouble() > profile.forwardProbability) {
      dropped++;
      return;
    }
    // Jitter: desincroniza los reenvíos para no saturar el medio.
    final delay = Duration(milliseconds: _random.nextInt(profile.rebroadcastJitterMs + 1));
    late Timer t;
    t = Timer(delay, () async {
      _pendingForwards.remove(t);
      if (_state == TransportState.idle) return;
      forwarded++;
      try {
        await link.send(env.forwarded().encode());
      } catch (e) {
        debugPrint('MeshTransport: fallo al reenviar ${env.id}: $e');
      }
    });
    _pendingForwards.add(t);
  }

  // ---- Dedupe ----

  bool _isSeen(String id) => _seen.containsKey(id);

  void _markSeen(String id) {
    _seen[id] = DateTime.now();
    _evict();
  }

  void _evict() {
    final now = DateTime.now();
    // Por edad.
    _seen.removeWhere((_, t) => now.difference(t) > profile.seenTtl);
    // Por tamaño (expulsa los más antiguos, que están al frente).
    while (_seen.length > profile.maxSeen) {
      _seen.remove(_seen.keys.first);
    }
  }

  String _newId() {
    // Id compacto y único por nodo: 4 bytes aleatorios + contador en base36.
    final bytes = List<int>.generate(4, (_) => _random.nextInt(256));
    final r = base64Url.encode(bytes).replaceAll('=', '');
    return '$r${(_counter++).toRadixString(36)}';
  }

  @override
  Future<void> stop() async {
    for (final t in _pendingForwards) {
      t.cancel();
    }
    _pendingForwards.clear();
    await _linkStateSub?.cancel();
    await _linkInSub?.cancel();
    _linkStateSub = _linkInSub = null;
    await link.stop();
    _seen.clear();
    _setState(TransportState.idle);
  }
}
