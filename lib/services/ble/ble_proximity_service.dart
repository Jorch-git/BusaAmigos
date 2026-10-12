import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import '../../utils/short_id.dart';

/// Lectura de proximidad por BLE entre miembros del grupo.
///
/// CÓMO FUNCIONA (y por qué con dos paquetes):
///  - `flutter_blue_plus` SOLO puede escanear (rol "central"). No puede
///    emitir anuncios. Por eso, para que los demás nos "vean", usamos
///    `flutter_ble_peripheral`, que sí emite advertising (rol "peripheral").
///  - EMITIMOS un anuncio BLE que incluye un identificador corto de 16 bits
///    derivado de nuestro memberId (ver ShortId). Como Android randomiza la
///    MAC, ese short id en el payload es lo que permite a los demás saber que
///    el anuncio es nuestro.
///  - ESCANEAMOS los anuncios de alrededor. Cuando vemos uno con un short id
///    que corresponde a un miembro del grupo, leemos su RSSI (intensidad de
///    señal). Más cerca de 0 = más cerca físicamente.
///
/// LÍMITES HONESTOS:
///  - Android↔Android: funciona. Es el caso principal.
///  - iOS: el manufacturer data NO se puede emitir en iOS (limitación de
///    Apple). Por eso, para iPhones, la app cae al GPS (lo maneja el algoritmo
///    de distancia, no este servicio).
///  - El RSSI es RUIDOSO (cuerpos, bolsillos, orientación lo afectan ±10 dB).
///    Por eso lo usamos para "muy cerca / cerca", no para metros exactos.
///  - Para ahorrar batería, este servicio se arranca SOLO en las pantallas de
///    brújula/radar y se detiene al salir de ellas.
class BleProximityService {
  BleProximityService._();
  static final BleProximityService instance = BleProximityService._();

  /// ID de fabricante para el manufacturer data (cualquiera reservado/propio).
  /// 0xFFFF es el id de pruebas/no-asignado, válido para uso interno.
  static const int manufacturerId = 0xFFFF;

  final _peripheral = FlutterBlePeripheral();

  /// RSSI más reciente por short id de miembro: { shortId: rssi(dBm) }.
  final Map<int, int> _rssiByShortId = {};

  /// Marca de tiempo de la última lectura por short id (para expirar viejos).
  final Map<int, DateTime> _lastSeenByShortId = {};

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _running = false;
  bool _advertising = false;
  String? _selfShortHex;

  bool get isRunning => _running;
  bool get isAdvertising => _advertising;

  /// Stream que emite cada vez que se actualizan las lecturas de RSSI.
  final _updatesCtrl = StreamController<void>.broadcast();
  Stream<void> get updates => _updatesCtrl.stream;

  /// Arranca advertising + scanning. [selfMemberId] es nuestro id; lo
  /// anunciamos como short id para que los demás nos reconozcan.
  Future<void> start({required String selfMemberId}) async {
    if (_running) return;
    _running = true;

    final selfShort = ShortId.of(selfMemberId);
    _selfShortHex = selfShort.toRadixString(16);

    await _startAdvertising(selfMemberId);
    await _startScanning();
    debugPrint('BleProximity: iniciado (selfShort=$selfShort)');
  }

  Future<void> _startAdvertising(String selfMemberId) async {
    try {
      // Verificar soporte primero. En flutter_ble_peripheral 2.x, isSupported
      // es una PROPIEDAD async (getter), no un método: se accede SIN paréntesis.
      final supported = await _peripheral.isSupported;
      if (!supported) {
        _advertising = false;
        debugPrint('BleProximity: advertising NO soportado en este dispositivo');
        return;
      }

      final bytes = ShortId.bytesOf(selfMemberId);
      final data = AdvertiseData(
        includeDeviceName: false,
        manufacturerId: manufacturerId,
        manufacturerData: Uint8List.fromList(bytes),
      );
      // Usamos solo AdvertiseData (lo único soportado en iOS y estable en
      // Android). No pasamos AdvertiseSettings/SetParameters para máxima
      // compatibilidad entre versiones.
      await _peripheral.start(advertiseData: data);
      _advertising = true;
      debugPrint('BleProximity: advertising iniciado');
    } catch (e) {
      // En iOS (manufacturer data no soportado) o dispositivos sin advertising,
      // esto falla: no pasa nada, seguimos escaneando y para nosotros se usa GPS.
      _advertising = false;
      debugPrint('BleProximity: advertising no disponible: $e');
    }
  }

  Future<void> _startScanning() async {
    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        var changed = false;
        for (final r in results) {
          final mfd = r.advertisementData.manufacturerData;
          // manufacturerData es { companyId: bytes }.
          final bytes = mfd[manufacturerId];
          if (bytes == null || bytes.length < 2) continue;
          final shortId = ShortId.fromBytes(bytes[0], bytes[1]);
          // No nos contamos a nosotros mismos.
          if (shortId.toRadixString(16) == _selfShortHex) continue;
          _rssiByShortId[shortId] = r.rssi;
          _lastSeenByShortId[shortId] = DateTime.now();
          changed = true;
        }
        if (changed && !_updatesCtrl.isClosed) {
          _updatesCtrl.add(null);
        }
      });
      debugPrint('BleProximity: scanning iniciado');
    } catch (e) {
      debugPrint('BleProximity: error al escanear: $e');
    }
  }

  /// Devuelve el RSSI más reciente para un miembro (por su id largo), o `null`
  /// si no lo hemos visto por BLE recientemente (>10 s se considera viejo).
  int? rssiForMember(String memberId) {
    final shortId = ShortId.of(memberId);
    final seen = _lastSeenByShortId[shortId];
    if (seen == null) return null;
    if (DateTime.now().difference(seen).inSeconds > 10) {
      // Lectura vieja: el miembro pudo alejarse del alcance BLE.
      return null;
    }
    return _rssiByShortId[shortId];
  }

  /// Detiene advertising + scanning (al salir de brújula/radar). Ahorra batería.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _scanSub?.cancel();
      _scanSub = null;
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('BleProximity: error deteniendo scan: $e');
    }
    if (_advertising) {
      try {
        await _peripheral.stop();
      } catch (e) {
        debugPrint('BleProximity: error deteniendo advertising: $e');
      }
      _advertising = false;
    }
    _rssiByShortId.clear();
    _lastSeenByShortId.clear();
    debugPrint('BleProximity: detenido');
  }

  /// Para diagnóstico en la Consola: lecturas actuales.
  Map<int, int> get currentReadings => Map.unmodifiable(_rssiByShortId);
}
