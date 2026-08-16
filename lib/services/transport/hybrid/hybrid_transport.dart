import 'dart:async';
import 'dart:collection';

import '../transport_service.dart';
import '../mesh/mesh_transport.dart';
import '../relay/relay_transport.dart';

/// Combina dos caminos y los presenta como UN solo transporte:
///   - [mesh]  : malla local multi-hop (offline, gratis, sin servidor).
///   - [relay] : tu servidor WebSocket (opcional). Da alcance global y cruce
///               iOS<->Android cuando hay internet.
///
/// Envía por AMBOS a la vez. Como un mensaje puede llegar por los dos caminos,
/// deduplica en recepción por el contenido del blob (que es idéntico byte a
/// byte cuando es el mismo mensaje, porque el cifrado se hizo una sola vez
/// antes de entregarlo aquí).
///
/// Filosofía: si hay internet, el mensaje llega lejos por el relay; si no, el
/// mesh local lo lleva de salto en salto. Nunca dependes de un tercero: sin
/// relay, el híbrido funciona igual, solo en modo local. Esto cubre lo que
/// hace Bridgefy (mesh local) y además lo que NO hace (alcance global).
class HybridTransport implements TransportService {
  HybridTransport(this.mesh, {this.relay, this.dedupeTtl = const Duration(minutes: 5), this.maxDedupe = 5000});

  final MeshTransport mesh;
  final RelayTransport? relay;
  final Duration dedupeTtl;
  final int maxDedupe;

  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();

  TransportState _state = TransportState.idle;
  final LinkedHashMap<String, DateTime> _seenBlobs = LinkedHashMap();

  final List<StreamSubscription> _subs = [];

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach {
    if (relay?.currentState == TransportState.connected) return TransportReach.global;
    return mesh.reach;
  }

  bool get hasRelay => relay != null;

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    _subs.add(mesh.incomingStream.listen(_onIncoming));
    _subs.add(mesh.stateStream.listen((_) => _recomputeState()));
    await mesh.start(groupCode: groupCode, selfId: selfId);

    final r = relay;
    if (r != null) {
      _subs.add(r.incomingStream.listen(_onIncoming));
      _subs.add(r.stateStream.listen((_) => _recomputeState()));
      await r.start(groupCode: groupCode, selfId: selfId);
    }
    _recomputeState();
  }

  @override
  Future<void> send(String encryptedBlob, {bool reliable = false}) async {
    // Manda por ambos caminos en paralelo. El receptor deduplica.
    // El flag reliable se propaga al mesh (que implementa ACK + reintentos).
    await Future.wait([
      mesh.send(encryptedBlob, reliable: reliable),
      if (relay != null) relay!.send(encryptedBlob, reliable: reliable),
    ]);
  }

  void _onIncoming(String blob) {
    final now = DateTime.now();
    _seenBlobs.removeWhere((_, t) => now.difference(t) > dedupeTtl);
    if (_seenBlobs.containsKey(blob)) return; // ya entregado por el otro camino
    _seenBlobs[blob] = now;
    while (_seenBlobs.length > maxDedupe) {
      _seenBlobs.remove(_seenBlobs.keys.first);
    }
    _incomingCtrl.add(blob);
  }

  void _recomputeState() {
    final states = <TransportState>[
      mesh.currentState,
      if (relay != null) relay!.currentState,
    ];
    TransportState combined;
    if (states.contains(TransportState.connected)) {
      combined = TransportState.connected;
    } else if (states.contains(TransportState.degraded)) {
      combined = TransportState.degraded;
    } else if (states.contains(TransportState.connecting)) {
      combined = TransportState.connecting;
    } else if (states.isNotEmpty && states.every((s) => s == TransportState.error)) {
      combined = TransportState.error;
    } else {
      combined = TransportState.idle;
    }
    if (combined != _state) {
      _state = combined;
      if (!_stateCtrl.isClosed) _stateCtrl.add(combined);
    }
  }

  @override
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await mesh.stop();
    await relay?.stop();
    _seenBlobs.clear();
    _state = TransportState.idle;
    if (!_stateCtrl.isClosed) _stateCtrl.add(_state);
  }
}
