import 'dart:math' as math;

import '../models/position.dart';

/// Resultado de calcular distancia entre dos miembros, con la fuente que
/// se usó para que la UI pueda comunicarla al usuario ("aprox por GPS",
/// "aprox por señal").
class DistanceResult {
  final double meters;
  final DistanceSource source;

  /// Error estimado en metros. La UI puede mostrar "±N m".
  final double? errorMeters;

  /// Rumbo (bearing) desde el observador hacia el objetivo, en grados
  /// donde 0 = norte. `null` si solo tenemos RSSI (no hay dirección).
  final double? bearing;

  const DistanceResult({
    required this.meters,
    required this.source,
    this.errorMeters,
    this.bearing,
  });
}

enum DistanceSource { gps, rssi, none }

/// Cálculos geográficos y de RSSI.
class DistanceCalculator {
  /// Radio de la Tierra en metros (aprox. para Haversine).
  static const double _earthRadius = 6371000;

  /// Distancia en metros entre dos puntos GPS (fórmula Haversine).
  static double haversine(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.asin(math.sqrt(a));
    return _earthRadius * c;
  }

  /// Rumbo inicial desde A hacia B en grados (0=N, 90=E). Forward azimuth.
  static double bearing(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    final dLng = _toRad(lng2 - lng1);
    final y = math.sin(dLng) * math.cos(_toRad(lat2));
    final x = math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.cos(dLng);
    final brng = math.atan2(y, x);
    return (_toDeg(brng) + 360) % 360;
  }

  /// Distancia aproximada por RSSI BLE. Heredada del proyecto anterior,
  /// usable solo a corta distancia (<15 m con buena calibración).
  ///
  /// [rssi] dBm. [txPower] potencia a 1 m (default -59 es razonable para
  /// celulares modernos como anunciantes BLE genéricos).
  static double rssiDistance(int rssi, {int txPower = -59, double n = 2.5}) {
    if (rssi >= 0) return -1;
    return math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  /// Calcula la mejor distancia disponible entre la posición [self] y el
  /// peer en [other]. Si ambas posiciones tienen GPS, usa GPS. Si solo
  /// hay RSSI, usa RSSI. Si no hay nada, devuelve [DistanceSource.none].
  ///
  /// La UI puede pedir el bearing por separado para no recalcular.
  static DistanceResult between(Position? self, Position? other) {
    if (self == null || other == null) {
      return const DistanceResult(meters: 0, source: DistanceSource.none);
    }

    if (self.hasGps && other.hasGps) {
      final d = haversine(
        self.latitude!, self.longitude!,
        other.latitude!, other.longitude!,
      );
      // Error combinado: suma cuadrática de las accuracys disponibles.
      final selfAcc = self.accuracy ?? 5;
      final otherAcc = other.accuracy ?? 5;
      final err = math.sqrt(selfAcc * selfAcc + otherAcc * otherAcc);
      final brng = bearing(
        self.latitude!, self.longitude!,
        other.latitude!, other.longitude!,
      );
      return DistanceResult(
        meters: d,
        source: DistanceSource.gps,
        errorMeters: err,
        bearing: brng,
      );
    }

    if (other.hasRssi) {
      return DistanceResult(
        meters: other.rssiDistance!,
        source: DistanceSource.rssi,
      );
    }

    return const DistanceResult(meters: 0, source: DistanceSource.none);
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;
}
