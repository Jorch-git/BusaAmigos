import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../transport_service.dart';

/// Relay por WebSocket contra TU PROPIO servidor (Node/Go/Rust), opcional.
///
/// Para qué sirve dentro del híbrido:
///   - Da alcance GLOBAL cuando hay internet: cualquier miembro del grupo es
///     alcanzable aunque esté lejos (no solo los que tienes a 100 m por mesh).
///   - Cruza plataformas: iOS <-> Android funcionan sin problema vía relay
///     (lo que NO es posible offline). Esta es la ventaja sobre Bridgefy.
///
/// El servidor es TRIVIAL y no ve nada en claro: recibe
/// `{"group": code, "from": id, "blob": "..."}` y lo retransmite al resto del
/// canal `group`. El `blob` ya está cifrado E2E, así que el server solo
/// necesita evitar abuso (rate limit, tamaño máximo). Ejemplo mínimo en Node:
///
/// ```js
/// const { WebSocketServer } = require('ws');
/// const wss = new WebSocketServer({ port: 8080 });
/// const chans = new Map();
/// wss.on('connection', (ws) => {
///   ws.on('message', (raw) => {
///     let m; try { m = JSON.parse(raw); } catch { return; }
///     const g = m.group; if (!g) return;
///     if (!chans.has(g)) chans.set(g, new Set());
///     chans.get(g).add(ws); ws._g = g;
///     for (const peer of chans.get(g)) if (peer !== ws && peer.readyState === 1) peer.send(raw);
///   });
///   ws.on('close', () => chans.get(ws._g)?.delete(ws));
/// });
/// ```
///
/// Si no pasas URL, simplemente no uses este transporte: el híbrido funciona
/// solo con el mesh local. Así NO dependes de ningún servicio de terceros.
class RelayTransport implements TransportService {
  RelayTransport(this.url, {this.maxBackoff = const Duration(seconds: 15)});

  /// URL del servidor: `ws://host:puerto` o `wss://host` (TLS recomendado).
  final String url;
  final Duration maxBackoff;

  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();

  WebSocket? _socket;
  StreamSubscription? _socketSub;
  TransportState _state = TransportState.idle;
  String? _selfId;
  String? _groupCode;

  bool _stopped = false;
  Duration _backoff = const Duration(milliseconds: 500);
  Timer? _reconnectTimer;

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach =>
      _state == TransportState.connected ? TransportReach.global : TransportReach.none;

  void _setState(TransportState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    _selfId = selfId;
    _groupCode = groupCode;
    _stopped = false;
    await _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    _setState(TransportState.connecting);
    try {
      final socket = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 8));
      _socket = socket;
      _backoff = const Duration(milliseconds: 500);
      _setState(TransportState.connected);
      debugPrint('RelayTransport: conectado a $url');

      _socketSub = socket.listen(
        _onMessage,
        onError: (e) {
          debugPrint('RelayTransport: error socket: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('RelayTransport: socket cerrado');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('RelayTransport: no se pudo conectar: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      final blob = m['blob'] as String?;
      final from = m['from'] as String?;
      final group = m['group'] as String?;
      if (blob != null && from != _selfId && group == _groupCode) {
        _incomingCtrl.add(blob);
      }
    } catch (e) {
      debugPrint('RelayTransport: mensaje malformado: $e');
    }
  }

  void _scheduleReconnect() {
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    if (_stopped) return;
    _setState(TransportState.degraded);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff, _connect);
    // Backoff exponencial con tope.
    final next = _backoff * 2;
    _backoff = next > maxBackoff ? maxBackoff : next;
  }

  @override
  Future<void> send(String encryptedBlob, {bool reliable = false}) async {
    final socket = _socket;
    if (socket == null || _state != TransportState.connected) return;
    try {
      socket.add(jsonEncode({
        'group': _groupCode,
        'from': _selfId,
        'blob': encryptedBlob,
      }));
    } catch (e) {
      debugPrint('RelayTransport: error enviando: $e');
      _scheduleReconnect();
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    await _socketSub?.cancel();
    await _socket?.close();
    _socketSub = null;
    _socket = null;
    _setState(TransportState.idle);
  }
}
