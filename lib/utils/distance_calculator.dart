import 'dart:math' as math;

import '../models/position.dart';
import '../services/ble/rssi_calibration.dart';

/// Resultado de calcular distancia entre dos miembros.
///
/// v15: fusión RSSI + GPS con rangos escalonados. La distancia se reporta en
/// escalones honestos (<1 m, ~5 m, ~10 m, ~15 m, ~20 m, ~25 m, 25 m+) porque
/// ni el RSSI ni el GPS tienen resolución para metros exactos. Mejor un rango
/// confiable que un número falso.
class DistanceResult {
  final double meters;
  final DistanceSource source;
  final double? errorMeters;
  final double? bearing;
  final DistanceConfidence confidence;

  const DistanceResult({
    required this.meters,
    required this.source,
    this.errorMeters,
    this.bearing,
    this.confidence = DistanceConfidence.none,
  });

  bool get isVeryClose => confidence == DistanceConfidence.veryClose;
  bool get hasNoData => source == DistanceSource.none;

  /// Texto honesto en escalones para mostrar en la UI.
  String get label {
    if (source == DistanceSource.none) return 'Sin ubicación';
    if (confidence == DistanceConfidence.veryClose) {
      // Muy cerca: si la estimación es de menos de 1 m, lo decimos.
      if (meters < 1.0) return 'Menos de 1 m';
      return 'Muy cerca';
    }
    return _stepLabel(meters);
  }

  /// Versión compacta para el radar.
  String get labelShort {
    if (source == DistanceSource.none) return '—';
    if (confidence == DistanceConfidence.veryClose) {
      if (meters < 1.0) return '<1 m';
      return 'Muy cerca';
    }
    return _stepLabel(meters);
  }

  /// Convierte metros a un escalón de 5 en 5: ~5, ~10, ~15, ~20, ~25, 25 m+.
  static String _stepLabel(double m) {
    if (m < 3) return 'Muy cerca';
    if (m <= 7) return '~5 m';
    if (m <= 12) return '~10 m';
    if (m <= 17) return '~15 m';
    if (m <= 22) return '~20 m';
    if (m <= 27) return '~25 m';
    return '25 m+';
  }
}

enum DistanceSource {
  /// Distancia por fuerza de señal BLE (proximidad fina a corta distancia).
  rssi,

  /// Distancia por GPS (Haversine).
  gps,

  /// Combinación de ambos.
  fused,

  none,
}

enum DistanceConfidence { none, veryClose, approximate, good }

/// Cálculos geográficos + fusión RSSI/GPS.
class DistanceCalculator {
  static const double _earthRadius = 6371000;

  /// A esta distancia o menos, consideramos "muy cerca" (el detalle exacto no
  /// importa porque ya se ven).
  static const double veryCloseThresholdMeters = 8;

  /// RSSI a partir del cual consideramos a alguien "muy cerca" sin más cuentas
  /// (señal muy fuerte = encima). -55 dBm ≈ <2-3 m en la mayoría de casos.
  static const int veryCloseRssiThreshold = -55;

  /// Por debajo de este RSSI la señal es tan débil que no la usamos para
  /// distancia (el GPS es mejor a esas distancias). -85 dBm ≈ >15-20 m.
  static const int usableRssiFloor = -85;

  static double haversine(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.asin(math.sqrt(a));
    return _earthRadius * c;
  }

  static double bearing(double lat1, double lng1, double lat2, double lng2) {
    final dLng = _toRad(lng2 - lng1);
    final y = math.sin(dLng) * math.cos(_toRad(lat2));
    final x = math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.cos(dLng);
    final brng = math.atan2(y, x);
    return (_toDeg(brng) + 360) % 360;
  }

  /// Distancia por RSSI usando la calibración activa.
  static double rssiDistance(int rssi, {int? txPower, double? n}) {
    if (rssi >= 0) return -1;
    final tx = txPower ?? RssiCalibration.instance.txPowerAt1m.round();
    final nn = n ?? RssiCalibration.instance.pathLossN;
    return math.pow(10, (tx - rssi) / (10 * nn)).toDouble();
  }

  /// ALGORITMO DE FUSIÓN (el corazón de v15).
  ///
  /// Prioridad de fuentes:
  ///  1. RSSI fuerte (≥ -55 dBm): "muy cerca", gana sobre todo. Es el caso de
  ///     dos Android pegados — el GPS diría números erráticos, el RSSI no.
  ///  2. RSSI usable (-55 a -85) Y GPS poco confiable: usar RSSI (mejor a
  ///     corta distancia donde el GPS falla).
  ///  3. GPS confiable (error < distancia): usar GPS con rangos escalonados.
  ///  4. RSSI usable sin GPS confiable: usar RSSI aproximado.
  ///  5. Solo GPS (aunque ruidoso): última opción, marcado como aproximado.
  ///
  /// El [rssi] viene del BleProximityService (null si no hay lectura BLE, p.ej.
  /// el peer es iPhone o está fuera de alcance BLE → caemos a GPS).
  static DistanceResult between(Position? self, Position? other, {int? rssi}) {
    // --- Datos GPS disponibles ---
    final hasGps = self != null && other != null && self.hasGps && other.hasGps;
    double? gpsDist;
    double? gpsErr;
    double? brng;
    if (hasGps) {
      gpsDist = haversine(
          self.latitude!, self.longitude!, other.latitude!, other.longitude!);
      final selfAcc = self.accuracy ?? 5;
      final otherAcc = other.accuracy ?? 5;
      gpsErr = math.sqrt(selfAcc * selfAcc + otherAcc * otherAcc);
      brng = bearing(
          self.latitude!, self.longitude!, other.latitude!, other.longitude!);
    }

    // --- Datos RSSI disponibles ---
    // Tomamos el rssi pasado como argumento (lectura BLE en vivo) o, si no,
    // el que venga embebido en la posición del peer.
    final effectiveRssi = rssi ?? other?.rssi;
    final hasUsableRssi =
        effectiveRssi != null && effectiveRssi >= usableRssiFloor;

    // 1. RSSI MUY fuerte → muy cerca, gana sobre todo.
    if (effectiveRssi != null && effectiveRssi >= veryCloseRssiThreshold) {
      final d = rssiDistance(effectiveRssi);
      return DistanceResult(
        meters: d,
        source: hasGps ? DistanceSource.fused : DistanceSource.rssi,
        bearing: brng, // si hay GPS, conservamos la dirección
        confidence: DistanceConfidence.veryClose,
      );
    }

    // 2 y 4. RSSI usable y (no hay GPS confiable). El GPS es "confiable" si su
    // error es claramente menor que la distancia que mide.
    final gpsReliable =
        hasGps && gpsErr != null && gpsDist != null && gpsErr < gpsDist * 0.6 &&
            gpsDist > veryCloseThresholdMeters;

    if (hasUsableRssi && !gpsReliable) {
      final d = rssiDistance(effectiveRssi);
      final conf = d <= veryCloseThresholdMeters
          ? DistanceConfidence.veryClose
          : DistanceConfidence.approximate;
      return DistanceResult(
        meters: d,
        source: hasGps ? DistanceSource.fused : DistanceSource.rssi,
        bearing: brng,
        confidence: conf,
      );
    }

    // 3 y 5. Camino GPS (con o sin confiabilidad alta).
    if (hasGps) {
      final DistanceConfidence conf;
      if (gpsDist! <= veryCloseThresholdMeters || gpsDist <= gpsErr!) {
        conf = DistanceConfidence.veryClose;
      } else if (gpsErr > gpsDist * 0.4) {
        conf = DistanceConfidence.approximate;
      } else {
        conf = DistanceConfidence.good;
      }
      return DistanceResult(
        meters: gpsDist,
        source: DistanceSource.gps,
        errorMeters: gpsErr,
        bearing: brng,
        confidence: conf,
      );
    }

    // Sin nada utilizable.
    return const DistanceResult(
        meters: 0, source: DistanceSource.none,
        confidence: DistanceConfidence.none);
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;
}
