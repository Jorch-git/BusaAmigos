
/// Parámetros ajustables del beacon y del muestreo de sensores. Pensado para
/// exponerse en la Consola/Settings y permitir afinado fino durante el
/// desarrollo sin recompilar.
///
/// Es inmutable: para cambiar un valor usa [copyWith] y reasigna en el
/// servicio correspondiente.
class BeaconConfig {
  /// Cada cuánto se emite la posición/movimiento a los demás. Jorge pidió
  /// 1 s por defecto; bajarlo da más fluidez a costa de batería y datos.
  final Duration beaconInterval;

  /// Periodo de muestreo de los sensores inerciales. Más rápido = mejor
  /// detección de pasos y rumbo, más CPU/batería. `gameInterval` (~20 ms)
  /// es un buen punto medio para PDR.
  final Duration sensorSamplingPeriod;

  /// Si true usa una zancada fija (más predecible); si false la estima por
  /// amplitud de aceleración (Weinberg).
  final bool useFixedStride;

  /// Zancada fija en metros cuando [useFixedStride] es true. ~0.75 m es un
  /// promedio adulto razonable; afínalo a la estatura del usuario.
  final double fixedStrideMeters;

  /// Comprimir el payload (gzip) antes de cifrar. Reduce datos en mensajes
  /// con varios campos. Para payloads diminutos puede no valer la pena, por
  /// eso el codec decide por tamaño, pero este flag permite forzarlo off.
  final bool compress;

  /// Incluir lectura cruda de sensores en el beacon (rumbo, inclinación,
  /// pasos, cadencia). Apágalo para minimizar datos al máximo.
  final bool includeMotion;

  /// Precisión GPS (m) por debajo de la cual consideramos el fix "bueno" y
  /// re-anclamos el dead reckoning.
  final double gpsAnchorAccuracy;

  const BeaconConfig({
    this.beaconInterval = const Duration(seconds: 1),
    this.sensorSamplingPeriod = const Duration(milliseconds: 20),
    this.useFixedStride = false,
    this.fixedStrideMeters = 0.75,
    this.compress = true,
    this.includeMotion = true,
    this.gpsAnchorAccuracy = 12.0,
  });

  BeaconConfig copyWith({
    Duration? beaconInterval,
    Duration? sensorSamplingPeriod,
    bool? useFixedStride,
    double? fixedStrideMeters,
    bool? compress,
    bool? includeMotion,
    double? gpsAnchorAccuracy,
  }) {
    return BeaconConfig(
      beaconInterval: beaconInterval ?? this.beaconInterval,
      sensorSamplingPeriod: sensorSamplingPeriod ?? this.sensorSamplingPeriod,
      useFixedStride: useFixedStride ?? this.useFixedStride,
      fixedStrideMeters: fixedStrideMeters ?? this.fixedStrideMeters,
      compress: compress ?? this.compress,
      includeMotion: includeMotion ?? this.includeMotion,
      gpsAnchorAccuracy: gpsAnchorAccuracy ?? this.gpsAnchorAccuracy,
    );
  }

  Map<String, dynamic> toJson() => {
        'beaconMs': beaconInterval.inMilliseconds,
        'sampleMs': sensorSamplingPeriod.inMilliseconds,
        'fixedStride': useFixedStride,
        'strideM': fixedStrideMeters,
        'compress': compress,
        'motion': includeMotion,
        'gpsAnchorAcc': gpsAnchorAccuracy,
      };

  factory BeaconConfig.fromJson(Map<String, dynamic> j) => BeaconConfig(
        beaconInterval: Duration(milliseconds: (j['beaconMs'] as num?)?.toInt() ?? 1000),
        sensorSamplingPeriod:
            Duration(milliseconds: (j['sampleMs'] as num?)?.toInt() ?? 20),
        useFixedStride: (j['fixedStride'] as bool?) ?? false,
        fixedStrideMeters: (j['strideM'] as num?)?.toDouble() ?? 0.75,
        compress: (j['compress'] as bool?) ?? true,
        includeMotion: (j['motion'] as bool?) ?? true,
        gpsAnchorAccuracy: (j['gpsAnchorAcc'] as num?)?.toDouble() ?? 12.0,
      );
}
