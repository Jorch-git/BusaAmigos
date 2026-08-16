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
/// Qué añade sobre el transporte base:
///   - **Store & forward**: si A y C no se ven pero ambos ven a B, el mensaje
///     de A salta por B hasta C.
///   - **Dedupe**: cada mensaje lleva un id; si ya lo vimos, no lo reprocesamos.
///   - **TTL + hop count**: el mensaje muere tras N saltos.
///   - **Gossip + jitter**: reenvío probabilístico con retardo aleatorio para
///     evitar tormentas de broadcast en multitudes.
///   - **ACK + reintentos (v20)**: para mensajes marcados `reliable` (chat,
///     SOS), el origen reintenta hasta recibir confirmación del destino. Las
///     posiciones NO usan esto (se renuevan solas cada segundo), así no
///     gastamos batería ni saturamos la malla.
///
/// Es agnóstico del contenido: el [payload] del sobre es el blob ya cifrado
/// E2E. Esta capa solo lee la cabecera de ruteo (en claro).
class MeshTransport implements TransportService {
  MeshTransport(this.link, {this.profile = MeshProfile.standard});

  final TransportService link;
  MeshProfile profile;

  // ---- Parámetros de fiabilidad (ACK + reintentos) ----
  /// Cada cuánto reintentamos un mensaje reliable no confirmado.
  static const _retryInterval = Duration(seconds: 3);

  /// Cuántas veces reintentamos antes de rendirnos (3s * 8 ≈ 24s de ventana).
  static const _maxRetries = 8;

  /// TTL de los ACK (cuántos saltos pueden dar de vuelta al origen).
  static const _ackTtl = 6;

  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();

  TransportState _state = TransportState.idle;
  String _selfId = '';
  final _random = Random();
  int _counter = 0;

  StreamSubscription? _linkStateSub;
  StreamSubscription? _linkInSub;

  /// Ids vistos -> momento en que se vieron (dedupe de mensajes de datos).
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();

  /// Ids de ACK vistos (dedupe de ACKs, separado de los datos).
  final LinkedHashMap<String, DateTime> _seenAcks = LinkedHashMap();

  final List<Timer> _pendingForwards = [];

  /// Mensajes reliable esperando ACK: id -> estado de reintento.
  final Map<String, _PendingReliable> _awaitingAck = {};

  // ---- Diagnóstico (para la consola de desarrollo) ----
  int originated = 0,
      delivered = 0,
      forwarded = 0,
      dropped = 0,
      duplicates = 0,
      acksSent = 0,
      acksReceived = 0,
      retries = 0,
      giveUps = 0;

  Map<String, dynamic> get meshStats => {
        'profile': profile.name,
        'ttl': profile.ttl,
        'seenIds': _seen.length,
        'originated': originated,
        'delivered': delivered,
        'forwarded': forwarded,
        'droppedGossip': dropped,
        'duplicates': duplicates,
        'awaitingAck': _awaitingAck.length,
        'acksSent': acksSent,
        'acksReceived': acksReceived,
        'retries': retries,
        'giveUps': giveUps,
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
  Future<void> send(String encryptedBlob, {bool reliable = false}) async {
    final id = _newId();
    _markSeen(id); // no reenviar mi propio eco si me vuelve por un vecino
    originated++;
    final env = MeshEnvelope(
      id: id,
      origin: _selfId,
      ttl: profile.ttl,
      hop: 0,
      reliable: reliable,
      payload: encryptedBlob,
    );

    // Si es reliable, lo guardamos para reintentar hasta recibir ACK.
    if (reliable) {
      _awaitingAck[id] = _PendingReliable(
        encoded: env.encode(),
        retriesLeft: _maxRetries,
        timer: _startRetryTimer(id),
      );
    }

    await link.send(env.encode());
  }

  Timer _startRetryTimer(String id) {
    return Timer.periodic(_retryInterval, (t) async {
      final pending = _awaitingAck[id];
      if (pending == null) {
        t.cancel();
        return;
      }
      if (pending.retriesLeft <= 0) {
        // Nos rendimos: ya no reintentamos más. El mensaje pudo no llegar a
        // todos, pero evitamos reintentar para siempre.
        t.cancel();
        _awaitingAck.remove(id);
        giveUps++;
        debugPrint('MeshTransport: sin ACK para $id tras $_maxRetries intentos');
        return;
      }
      if (_state == TransportState.idle) return;
      pending.retriesLeft--;
      retries++;
      try {
        // Reenviamos el mismo sobre (mismo id; los duplicados se filtran solos
        // en los demás, pero quien NO lo había recibido ahora sí lo recibe).
        await link.send(pending.encoded);
      } catch (e) {
        debugPrint('MeshTransport: error reintentando $id: $e');
      }
    });
  }

  void _onLinkData(String raw) {
    // ¿Es un ACK?
    final ack = MeshAck.tryParse(raw);
    if (ack != null) {
      _onAck(ack);
      return;
    }

    final env = MeshEnvelope.tryParse(raw);
    if (env == null) {
      // No es un sobre mesh (ghost de dev, blob legacy): pásalo tal cual.
      _incomingCtrl.add(raw);
      return;
    }

    if (_isSeen(env.id)) {
      duplicates++;
      // IMPORTANTE: aunque sea duplicado, si es reliable y va dirigido a la
      // malla, reenviamos el ACK de nuevo por si el primero se perdió. Pero
      // solo si nosotros somos un destinatario (no el origen).
      if (env.reliable && env.origin != _selfId) {
        _sendAck(env.id);
      }
      return;
    }
    _markSeen(env.id);

    // Entrega a la app solo si no lo originamos nosotros.
    if (env.origin != _selfId) {
      delivered++;
      _incomingCtrl.add(env.payload);

      // Si el mensaje pide confirmación, emitimos un ACK de vuelta al origen.
      if (env.reliable) {
        _sendAck(env.id);
      }
    }

    // Reenvío multi-hop.
    if (env.ttl > 0) _scheduleForward(env);
  }

  /// Emite un ACK confirmando [ackedId], que viajará por la malla al origen.
  void _sendAck(String ackedId) {
    final ack = MeshAck(
      ackId: _newId(),
      origin: _selfId,
      ttl: _ackTtl,
      hop: 0,
      ackedId: ackedId,
    );
    _markAckSeen(ack.ackId);
    acksSent++;
    try {
      link.send(ack.encode());
    } catch (e) {
      debugPrint('MeshTransport: error enviando ACK de $ackedId: $e');
    }
  }

  void _onAck(MeshAck ack) {
    if (_seenAcks.containsKey(ack.ackId)) {
      // ACK duplicado; aún así puede que necesitemos reenviarlo si no es para
      // nosotros, pero para evitar bucles solo lo procesamos una vez.
      return;
    }
    _markAckSeen(ack.ackId);

    // ¿Este ACK confirma un mensaje MÍO que estaba esperando?
    final pending = _awaitingAck.remove(ack.ackedId);
    if (pending != null) {
      pending.timer.cancel();
      acksReceived++;
      debugPrint('MeshTransport: ACK recibido para ${ack.ackedId}, confirmado');
      // No reenviamos: el ACK llegó a su destino (nosotros).
      return;
    }

    // No es para nosotros: reenviamos el ACK por la malla (multi-hop) para que
    // llegue al origen del mensaje.
    if (ack.ttl > 0) {
      final delay =
          Duration(milliseconds: _random.nextInt(profile.rebroadcastJitterMs + 1));
      late Timer t;
      t = Timer(delay, () async {
        _pendingForwards.remove(t);
        if (_state == TransportState.idle) return;
        try {
          await link.send(ack.forwarded().encode());
        } catch (e) {
          debugPrint('MeshTransport: error reenviando ACK: $e');
        }
      });
      _pendingForwards.add(t);
    }
  }

  void _scheduleForward(MeshEnvelope env) {
    // Gossip: en multitudes no hace falta que todos reenvíen.
    if (profile.forwardProbability < 1.0 &&
        _random.nextDouble() > profile.forwardProbability) {
      dropped++;
      return;
    }
    // Jitter: desincroniza los reenvíos para no saturar el medio.
    final delay =
        Duration(milliseconds: _random.nextInt(profile.rebroadcastJitterMs + 1));
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
    _evict(_seen);
  }

  void _markAckSeen(String id) {
    _seenAcks[id] = DateTime.now();
    _evict(_seenAcks);
  }

  void _evict(LinkedHashMap<String, DateTime> map) {
    final now = DateTime.now();
    map.removeWhere((_, t) => now.difference(t) > profile.seenTtl);
    while (map.length > profile.maxSeen) {
      map.remove(map.keys.first);
    }
  }

  String _newId() {
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
    for (final p in _awaitingAck.values) {
      p.timer.cancel();
    }
    _awaitingAck.clear();
    await _linkStateSub?.cancel();
    await _linkInSub?.cancel();
    _linkStateSub = _linkInSub = null;
    await link.stop();
    _seen.clear();
    _seenAcks.clear();
    _setState(TransportState.idle);
  }
}

/// Estado de un mensaje reliable esperando ACK.
class _PendingReliable {
  final String encoded;
  int retriesLeft;
  final Timer timer;

  _PendingReliable({
    required this.encoded,
    required this.retriesLeft,
    required this.timer,
  });
}
