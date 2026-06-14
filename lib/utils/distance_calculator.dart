import 'dart:math' as math;

import '../models/position.dart';

/// Resultado de calcular distancia entre dos miembros.
///
/// v14: ahora incluye un [label] honesto y una bandera [isVeryClose]. La idea:
/// a corta distancia el GPS miente (error de ±10-17 m puede ser MAYOR que la
/// distancia real). En vez de mostrar "1.7 m" cuando el error es ±17 m —lo
/// cual confunde porque a veces marca lejos a quien tienes al lado—, mostramos
/// un texto cualitativo como "Muy cerca". El número solo se muestra cuando es
/// confiable (la distancia es claramente mayor que el error).
class DistanceResult {
  final double meters;
  final DistanceSource source;

  /// Error estimado en metros. La UI puede mostrar "±N m".
  final double? errorMeters;

  /// Rumbo (bearing) desde el observador hacia el objetivo, en grados
  /// donde 0 = norte. `null` si solo tenemos RSSI (no hay dirección).
  final double? bearing;

  /// Nivel de confianza del cálculo de distancia.
  final DistanceConfidence confidence;

  const DistanceResult({
    required this.meters,
    required this.source,
    this.errorMeters,
    this.bearing,
    this.confidence = DistanceConfidence.none,
  });

  /// `true` cuando GPS/señal indican que están prácticamente encima (el error
  /// hace que el número exacto no tenga sentido). La UI muestra "Muy cerca".
  bool get isVeryClose => confidence == DistanceConfidence.veryClose;

  /// `true` cuando no hay datos para calcular distancia.
  bool get hasNoData => source == DistanceSource.none;

  /// Texto corto y honesto listo para mostrar en la UI.
  ///  - "Muy cerca"        cuando están prácticamente encima.
  ///  - "~24 m"            cuando el GPS es confiable.
  ///  - "~30 m aprox."     cuando hay distancia pero con incertidumbre alta.
  ///  - "Sin ubicación"    cuando no hay datos.
  String get label {
    switch (confidence) {
      case DistanceConfidence.none:
        return 'Sin ubicación';
      case DistanceConfidence.veryClose:
        return 'Muy cerca';
      case DistanceConfidence.approximate:
        // Redondeamos a múltiplos de 5 para no fingir precisión que no hay.
        final rounded = (meters / 5).round() * 5;
        final shown = rounded < 5 ? 5 : rounded;
        return '~$shown m aprox.';
      case DistanceConfidence.good:
        return '~${meters.toStringAsFixed(0)} m';
    }
  }

  /// Versión compacta para el radar (sin la palabra "aprox").
  String get labelShort {
    switch (confidence) {
      case DistanceConfidence.none:
        return '—';
      case DistanceConfidence.veryClose:
        return 'Muy cerca';
      case DistanceConfidence.approximate:
        final rounded = (meters / 5).round() * 5;
        final shown = rounded < 5 ? 5 : rounded;
        return '~$shown m';
      case DistanceConfidence.good:
        return '~${meters.toStringAsFixed(0)} m';
    }
  }
}

enum DistanceSource { gps, rssi, none }

/// Qué tan confiable es la distancia calculada.
enum DistanceConfidence {
  /// No hay datos suficientes.
  none,

  /// Están prácticamente encima; el error supera la distancia. Mostrar
  /// "Muy cerca" en vez de un número engañoso.
  veryClose,

  /// Hay distancia pero con incertidumbre alta (error es una fracción
  /// significativa de la distancia). Mostrar como aproximado.
  approximate,

  /// Distancia claramente mayor que el error. El número es confiable.
  good,
}

/// Cálculos geográficos y de RSSI.
class DistanceCalculator {
  static const double _earthRadius = 6371000;

  /// Umbral: si la distancia GPS es menor o igual a esto, consideramos que
  /// están "muy cerca" sin importar el número exacto (porque a esta escala el
  /// GPS no distingue). 8 m es un valor razonable: a esa distancia ya se ven.
  static const double veryCloseThresholdMeters = 8;

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

  static double rssiDistance(int rssi, {int txPower = -59, double n = 2.5}) {
    if (rssi >= 0) return -1;
    return math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  /// Calcula la distancia entre [self] y [other], clasificando la confianza.
  ///
  /// Lógica de confianza (esta es la corrección clave):
  ///  1. Si la distancia es muy chica (≤ umbral) O el error es mayor que la
  ///     distancia → "muy cerca" (el GPS no puede distinguir a esta escala).
  ///  2. Si el error es una fracción notable de la distancia (>40%) →
  ///     "aproximado".
  ///  3. Si la distancia es claramente mayor que el error → "good".
  static DistanceResult between(Position? self, Position? other) {
    if (self == null || other == null) {
      return const DistanceResult(
          meters: 0, source: DistanceSource.none,
          confidence: DistanceConfidence.none);
    }

    if (self.hasGps && other.hasGps) {
      final d = haversine(
        self.latitude!, self.longitude!,
        other.latitude!, other.longitude!,
      );
      final selfAcc = self.accuracy ?? 5;
      final otherAcc = other.accuracy ?? 5;
      // Error combinado: raíz de la suma de cuadrados de las precisiones.
      final err = math.sqrt(selfAcc * selfAcc + otherAcc * otherAcc);
      final brng = bearing(
        self.latitude!, self.longitude!,
        other.latitude!, other.longitude!,
      );

      // Clasificación de confianza.
      final DistanceConfidence conf;
      if (d <= veryCloseThresholdMeters || d <= err) {
        // Están encima, o el error es tan grande como la distancia: el número
        // no es confiable. Mejor decir "muy cerca".
        conf = DistanceConfidence.veryClose;
      } else if (err > d * 0.4) {
        // El error es una fracción importante de la distancia: aproximado.
        conf = DistanceConfidence.approximate;
      } else {
        conf = DistanceConfidence.good;
      }

      return DistanceResult(
        meters: d,
        source: DistanceSource.gps,
        errorMeters: err,
        bearing: brng,
        confidence: conf,
      );
    }

    if (other.hasRssi) {
      // RSSI: a corta distancia la señal fuerte indica proximidad. Si la
      // estimación es chica, "muy cerca"; si no, aproximado (RSSI nunca es
      // preciso en metros).
      final rd = other.rssiDistance!;
      final conf = rd <= veryCloseThresholdMeters
          ? DistanceConfidence.veryClose
          : DistanceConfidence.approximate;
      return DistanceResult(
        meters: rd,
        source: DistanceSource.rssi,
        confidence: conf,
      );
    }

    return const DistanceResult(
        meters: 0, source: DistanceSource.none,
        confidence: DistanceConfidence.none);
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;
}
