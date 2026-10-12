import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../utils/channel_id.dart';
import '../transport_service.dart';

/// Datos que publica un ancla en su endpoint `/info`.
class AnchorInfo {
  final int id;
  final String nombre;
  final String host;
  final double lat;
  final double lon;
  final double alt;
  final bool posicionFijada;
  final int clientes;

  const AnchorInfo({
    required this.id,
    required this.nombre,
    required this.host,
    required this.lat,
    required this.lon,
    required this.alt,
    required this.posicionFijada,
    required this.clientes,
  });

  static AnchorInfo? tryParse(String body, String host) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['ancla'] != true) return null;
      return AnchorInfo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        nombre: j['nombre'] as String? ?? 'Ancla',
        host: host,
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0,
        alt: (j['alt'] as num?)?.toDouble() ?? 0,
        posicionFijada: j['posFijada'] == true,
        clientes: (j['clientes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'Ancla $id ($nombre) en $host';
}

/// Transporte que usa un ancla LilyGo como relay, cuando hay una a la vista.
///
/// CÓMO ENCAJA CON LO QUE YA TIENES:
///  - Implementa la misma interfaz [TransportService] que los demás, así que
///    entra donde ya estaba el `RelayTransport` sin tocar arquitectura.
///  - Si NO hay ancla, no falla ni lanza excepciones: se queda en `degraded`
///    y `send()` no hace nada. La malla P2P sigue trabajando igual que hoy.
///    Por eso la app funciona con o sin anclas.
///
/// CÓMO DESCUBRE EL ANCLA:
///  El usuario se conecta a la WiFi del ancla desde los ajustes del teléfono
///  (SSID `buscamigos-ancla-NN`). Esta clase detecta sola que hay un ancla
///  sondeando `http://192.168.4.1/info` cada pocos segundos. No hace falta
///  ningún permiso extra ni paquetes nuevos: solo HTTP y WebSocket.
///
/// SEGURIDAD:
///  Al ancla se le manda el CANAL (hash del código), nunca el código. Ver
///  [ChannelId]. El ancla reenvía blobs cifrados que no puede leer.
class AnchorRelayTransport implements TransportService {
  /// Direcciones donde buscar un ancla. La primera es la IP por defecto del
  /// punto de acceso del ESP32. Puedes añadir IPs fijas si tus anclas
  /// cuelgan de un router propio.
  static List<String> hostsCandidatos = ['192.168.4.1'];

  /// Cada cuánto se busca un ancla cuando no hay ninguna conectada.
  static const Duration intervaloBusqueda = Duration(seconds: 6);

  /// Cada cuánto se comprueba que el ancla conectada sigue viva.
  static const Duration intervaloLatido = Duration(seconds: 20);

  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();
  final _anchorCtrl = StreamController<AnchorInfo?>.broadcast();

  TransportState _state = TransportState.idle;
  String? _canal;
  WebSocket? _socket;
  StreamSubscription? _socketSub;
  Timer? _busquedaTimer;
  Timer? _latidoTimer;
  AnchorInfo? _ancla;
  bool _activo = false;
  bool _conectando = false;

  /// Estadísticas para la consola de diagnóstico.
  int enviados = 0, recibidos = 0, reconexiones = 0;

  /// Ancla actualmente conectada, o `null` si estamos en modo malla pura.
  AnchorInfo? get ancla => _ancla;

  /// `true` si hay un ancla conectada y usable.
  bool get hayAncla => _socket != null && _ancla != null;

  /// Notifica cuando aparece o desaparece un ancla (para pintar la UI).
  Stream<AnchorInfo?> get anchorStream => _anchorCtrl.stream;

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach =>
      hayAncla ? TransportReach.local : TransportReach.none;

  void _setState(TransportState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    _activo = true;
    // El ancla recibe el HASH del código, nunca el código.
    _canal = await ChannelId.fromGroupCode(groupCode);
    _setState(TransportState.degraded); // sin ancla todavía: no es un error
    debugPrint('AnchorRelay: iniciado, canal=$_canal');

    _buscarAncla(); // intento inmediato
    _busquedaTimer?.cancel();
    _busquedaTimer = Timer.periodic(intervaloBusqueda, (_) {
      if (!hayAncla) _buscarAncla();
    });

    _latidoTimer?.cancel();
    _latidoTimer = Timer.periodic(intervaloLatido, (_) => _comprobarAncla());
  }

  /// Sondea los hosts candidatos buscando un ancla. Silencioso si no hay.
  Future<void> _buscarAncla() async {
    if (!_activo || _conectando || hayAncla) return;
    _conectando = true;
    try {
      for (final host in hostsCandidatos) {
        final info = await _pedirInfo(host);
        if (info != null) {
          debugPrint('AnchorRelay: encontrada $info');
          await _conectar(info);
          break;
        }
      }
    } finally {
      _conectando = false;
    }
  }

  Future<AnchorInfo?> _pedirInfo(String host) async {
    try {
      final resp = await http
          .get(Uri.parse('http://$host/info'))
          .timeout(const Duration(milliseconds: 1800));
      if (resp.statusCode != 200) return null;
      return AnchorInfo.tryParse(resp.body, host);
    } catch (_) {
      return null; // no hay ancla en esa IP; es lo normal
    }
  }

  Future<void> _conectar(AnchorInfo info) async {
    if (!_activo) return;
    _setState(TransportState.connecting);
    try {
      final url = 'ws://${info.host}:8080/ws?c=$_canal';
      final s = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 4));
      _socket = s;
      _ancla = info;

      _socketSub = s.listen(
        (data) {
          if (data is String && data.isNotEmpty) {
            recibidos++;
            if (!_incomingCtrl.isClosed) _incomingCtrl.add(data);
          }
        },
        onDone: _onSocketCerrado,
        onError: (e) {
          debugPrint('AnchorRelay: error de socket: $e');
          _onSocketCerrado();
        },
        cancelOnError: true,
      );

      _setState(TransportState.connected);
      if (!_anchorCtrl.isClosed) _anchorCtrl.add(info);
      debugPrint('AnchorRelay: conectado a $info');
    } catch (e) {
      debugPrint('AnchorRelay: no se pudo conectar a ${info.host}: $e');
      _socket = null;
      _ancla = null;
      _setState(TransportState.degraded);
    }
  }

  void _onSocketCerrado() {
    if (_socket == null && _ancla == null) return;
    debugPrint('AnchorRelay: ancla desconectada, vuelvo a malla P2P');
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    _ancla = null;
    reconexiones++;
    _setState(TransportState.degraded);
    if (!_anchorCtrl.isClosed) _anchorCtrl.add(null);
    // El timer de búsqueda la reencontrará sola si vuelve a aparecer.
  }

  /// Comprueba que el ancla sigue respondiendo; si no, corta y vuelve a malla.
  Future<void> _comprobarAncla() async {
    final a = _ancla;
    if (a == null || !_activo) return;
    final info = await _pedirInfo(a.host);
    if (info == null) {
      debugPrint('AnchorRelay: el ancla dejó de responder');
      try {
        await _socket?.close();
      } catch (_) {}
      _onSocketCerrado();
    } else {
      _ancla = info; // refrescamos clientes conectados, posición, etc.
      if (!_anchorCtrl.isClosed) _anchorCtrl.add(info);
    }
  }

  /// Envía por el ancla. Si no hay ancla, NO hace nada y NO falla:
  /// la malla P2P se encarga. Nunca lanza excepción, porque el transporte
  /// híbrido envía por ambos caminos a la vez y un fallo aquí no debe
  /// tumbar el envío por la malla.
  @override
  Future<void> send(String encryptedBlob, {bool reliable = false}) async {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(encryptedBlob);
      enviados++;
    } catch (e) {
      debugPrint('AnchorRelay: fallo al enviar: $e');
      _onSocketCerrado();
    }
  }

  @override
  Future<void> stop() async {
    _activo = false;
    _busquedaTimer?.cancel();
    _latidoTimer?.cancel();
    _busquedaTimer = _latidoTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _ancla = null;
    _setState(TransportState.idle);
    if (!_anchorCtrl.isClosed) _anchorCtrl.add(null);
  }

  /// Datos para la consola de diagnóstico.
  Map<String, dynamic> get anchorStats => {
        'hayAncla': hayAncla,
        'ancla': _ancla?.nombre ?? '—',
        'host': _ancla?.host ?? '—',
        'clientesEnAncla': _ancla?.clientes ?? 0,
        'canal': _canal ?? '—',
        'enviados': enviados,
        'recibidos': recibidos,
        'reconexiones': reconexiones,
      };
}
