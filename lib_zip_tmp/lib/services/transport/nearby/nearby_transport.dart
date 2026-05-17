import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart';

import '../transport_service.dart';

/// Transporte P2P para uso OFFLINE. Usa el plugin
/// `flutter_nearby_connections`, que internamente:
///   - En Android: usa Google Nearby Connections (BLE + Wi-Fi Direct).
///   - En iOS: usa Apple MultipeerConnectivity (BLE + Wi-Fi).
///
/// Limitaciones reales:
///   - El "groupCode" se publica como nombre de servicio, así que es visible
///     a otros dispositivos cercanos. NO es un secreto a este nivel — la
///     confidencialidad del CONTENIDO viene del cifrado E2E de
///     [GroupCrypto], no del transporte.
///   - Alcance Android↔Android ~30-100 m según interferencia.
///   - iOS↔iOS funciona bien. Android↔iOS NO es soportado por este plugin
///     (las dos APIs nativas son incompatibles). Si dos celulares de
///     plataformas distintas necesitan comunicarse SIN internet, no hay
///     solución 100% nativa hoy.
class NearbyTransport implements TransportService {
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();
  final _nearby = NearbyService();

  TransportState _state = TransportState.idle;
  String? _selfId;

  StreamSubscription? _stateSub;
  StreamSubscription? _dataSub;

  /// Peers actualmente conectados (id de dispositivo Nearby, no memberId).
  final Set<String> _connectedPeers = {};

  /// Getter público para que la consola de desarrollo pueda mostrar
  /// los peers P2P conectados. Devuelve una copia inmutable.
  Set<String> get connectedPeerIds => Set.unmodifiable(_connectedPeers);

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach => _connectedPeers.isEmpty
      ? TransportReach.none
      : TransportReach.local;

  void _setState(TransportState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    if (_state != TransportState.idle) return;
    _setState(TransportState.connecting);
    _selfId = selfId;

    try {
      const serviceType = 'buscamigos';

      debugPrint('NearbyTransport: Iniciando con serviceType=$serviceType, selfId=$selfId');

      await _nearby.init(
        serviceType: serviceType,
        deviceName: selfId,
        strategy: Strategy.P2P_CLUSTER,
        callback: (isRunning) async {
          debugPrint('NearbyTransport: Callback init, isRunning=$isRunning');
          if (isRunning) {
            await _nearby.stopAdvertisingPeer();
            await _nearby.stopBrowsingForPeers();
            await _nearby.startAdvertisingPeer();
            await _nearby.startBrowsingForPeers();
            debugPrint('NearbyTransport: Advertising y browsing iniciados');
          }
        },
      );

      _stateSub = _nearby.stateChangedSubscription(callback: (devices) {
        debugPrint('NearbyTransport: State changed, devices: ${devices.map((d) => '${d.deviceId}:${d.state}').join(', ')}');
        for (final d in devices) {
          switch (d.state) {
            case SessionState.notConnected:
              _connectedPeers.remove(d.deviceId);
              if (d.deviceId != selfId) {
                _nearby.invitePeer(deviceID: d.deviceId, deviceName: d.deviceName);
              }
              break;
            case SessionState.connecting:
              break;
            case SessionState.connected:
              _connectedPeers.add(d.deviceId);
              debugPrint('NearbyTransport: Connected to ${d.deviceId}');
              break;
          }
        }
        _refreshDegradedState();
      });

      _dataSub = _nearby.dataReceivedSubscription(callback: (data) {
        debugPrint('NearbyTransport: Data received: ${data['message']}');
        try {
          final parsed = jsonDecode(data['message'] as String) as Map<String, dynamic>;
          final blob = parsed['blob'] as String?;
          final from = parsed['from'] as String?;
          if (blob != null && from != selfId) {
            debugPrint('NearbyTransport: Forwarding message from $from');
            _incomingCtrl.add(blob);
          }
        } catch (e) {
          debugPrint('NearbyTransport: mensaje malformado ignorado: $e');
        }
      });

      _setState(TransportState.connected);
    } catch (e) {
      debugPrint('NearbyTransport: error en start: $e');
      _setState(TransportState.error);
      rethrow;
    }
  }

  void _refreshDegradedState() {
    if (_state == TransportState.idle) return;
    _setState(_connectedPeers.isEmpty
        ? TransportState.degraded
        : TransportState.connected);
  }

  @override
  Future<void> send(String encryptedBlob) async {
    debugPrint('NearbyTransport: Enviando mensaje a ${_connectedPeers.length} peers');
    if (_state == TransportState.idle) {
      debugPrint('NearbyTransport: Transporte inactivo, no se puede enviar');
      return;
    }
    final wire = jsonEncode({'from': _selfId, 'blob': encryptedBlob});
    debugPrint('NearbyTransport: Mensaje wire: $wire');
    for (final peerId in _connectedPeers) {
      try {
        debugPrint('NearbyTransport: Enviando a peer $peerId');
        await _nearby.sendMessage(peerId, wire);
        debugPrint('NearbyTransport: Mensaje enviado exitosamente a $peerId');
      } catch (e) {
        debugPrint('NearbyTransport: error enviando a $peerId: $e');
      }
    }
  }

  @override
  Future<void> stop() async {
    await _stateSub?.cancel();
    await _dataSub?.cancel();
    _stateSub = null;
    _dataSub = null;
    try {
      await _nearby.stopAdvertisingPeer();
      await _nearby.stopBrowsingForPeers();
    } catch (_) {}
    _connectedPeers.clear();
    _selfId = null;
    _setState(TransportState.idle);
  }
}
