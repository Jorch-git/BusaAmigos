import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Convierte RSSI (intensidad de señal BLE) en una distancia aproximada,
/// usando el modelo de pérdida de propagación log-distancia:
///
///     distancia = 10 ^ ((txPower - rssi) / (10 * n))
///
/// donde:
///  - `rssi`    = señal medida (dBm, negativa; -45 muy cerca, -90 lejos).
///  - `txPower` = RSSI esperado a 1 metro de distancia (referencia).
///  - `n`       = factor de atenuación del entorno (2 = espacio abierto,
///                2.5-3 = con cuerpos/obstáculos, típico en multitudes).
///
/// Los valores por defecto son razonables para teléfonos Samsung modernos.
/// El usuario puede ajustarlos desde la Consola (calibración manual) y se
/// guardan en disco.
class RssiCalibration {
  RssiCalibration._();
  static final RssiCalibration instance = RssiCalibration._();

  static const _fileName = 'buscamigos_rssi_calib.json';

  /// RSSI esperado a 1 metro. Default típico Samsung↔Samsung.
  double txPowerAt1m = -59;

  /// Factor de atenuación del entorno. 2.5 = realista en festival (cuerpos).
  double pathLossN = 2.5;

  /// Carga calibración guardada (si existe).
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      txPowerAt1m = (data['tx'] as num?)?.toDouble() ?? txPowerAt1m;
      pathLossN = (data['n'] as num?)?.toDouble() ?? pathLossN;
      debugPrint('RssiCalibration: cargada tx=$txPowerAt1m n=$pathLossN');
    } catch (e) {
      debugPrint('RssiCalibration: error cargando: $e');
    }
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'tx': txPowerAt1m, 'n': pathLossN}));
    } catch (e) {
      debugPrint('RssiCalibration: error guardando: $e');
    }
  }

  /// Ajuste manual: el usuario pone los teléfonos a [knownMeters] y registra
  /// el [measuredRssi]. Recalculamos txPower (si es a 1m) o n (si es a otra
  /// distancia conocida).
  Future<void> calibrateFrom({
    required int measuredRssi,
    required double knownMeters,
  }) async {
    if (knownMeters <= 0) return;
    if ((knownMeters - 1.0).abs() < 0.01) {
      // Calibración a 1 metro: ajusta directamente txPower.
      txPowerAt1m = measuredRssi.toDouble();
    } else {
      // A otra distancia: despejamos n del modelo log-distancia.
      //   rssi = txPower - 10*n*log10(d)  →  n = (txPower - rssi)/(10*log10(d))
      final denom = 10 * (math.log(knownMeters) / math.ln10);
      if (denom.abs() > 0.001) {
        pathLossN = (txPowerAt1m - measuredRssi) / denom;
        // Acotar a un rango físico sensato.
        pathLossN = pathLossN.clamp(1.5, 4.0);
      }
    }
    await save();
  }

  /// Convierte RSSI en metros estimados.
  double distanceFromRssi(int rssi) {
    if (rssi >= 0) return 0;
    final exp = (txPowerAt1m - rssi) / (10 * pathLossN);
    return math.pow(10, exp).toDouble();
  }

  /// Restaura los valores por defecto.
  Future<void> reset() async {
    txPowerAt1m = -59;
    pathLossN = 2.5;
    await save();
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
