/// Representa la posición conocida de un miembro.
///
/// Fuentes posibles:
///  - GPS real (lat/lng + accuracy): la principal cuando hay señal.
///  - RSSI BLE (rssiDistance): fallback a corta distancia.
///  - Dead reckoning (drNorth/drEast aplicados sobre el último GPS): rellena
///    huecos cuando el GPS se pierde.
///
/// Esta versión añade campos de MOVIMIENTO derivados de la fusión de sensores
/// (rumbo fusionado, confianza, inclinación, pasos, cadencia, estado). Todos
/// son opcionales y se serializan con claves cortas para minimizar datos.
class Position {
  final double? latitude;
  final double? longitude;
  final double? accuracy;

  /// Rumbo del miembro en grados (0=N, 90=E). Ahora es el rumbo FUSIONADO
  /// (giroscopio+magnetómetro), no el crudo del GPS.
  final double? heading;

  final double? rssiDistance;
  final int? rssi;
  final DateTime timestamp;

  // ---- Datos de fusión (nuevos) ----

  /// Confianza del rumbo [0..1].
  final double? headingConfidence;

  /// Inclinación del teléfono respecto a la horizontal (grados).
  final double? tilt;

  /// Pasos contados en la sesión.
  final int? steps;

  /// Cadencia (pasos/min).
  final double? cadence;

  /// Estado de movimiento: still/walking/running/unknown.
  final String? motion;

  /// Si la posición fue propagada por dead reckoning desde el último GPS
  /// (sin fix nuevo). La UI puede marcarla como menos confiable.
  final bool deadReckoned;

  const Position({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.heading,
    this.rssiDistance,
    this.rssi,
    required this.timestamp,
    this.headingConfidence,
    this.tilt,
    this.steps,
    this.cadence,
    this.motion,
    this.deadReckoned = false,
  });

  bool get hasGps => latitude != null && longitude != null;
  bool get hasRssi => rssiDistance != null;

  Duration get age => DateTime.now().difference(timestamp);
  bool get isFresh => age.inSeconds < 30;

  Map<String, dynamic> toJson() => {
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (accuracy != null) 'acc': accuracy,
        if (heading != null) 'hdg': heading,
        if (rssiDistance != null) 'rd': rssiDistance,
        if (rssi != null) 'rssi': rssi,
        if (headingConfidence != null) 'hc': headingConfidence,
        if (tilt != null) 'tilt': tilt,
        if (steps != null) 'st': steps,
        if (cadence != null) 'cad': cadence,
        if (motion != null) 'mo': motion,
        if (deadReckoned) 'dr': true,
        'ts': timestamp.toUtc().toIso8601String(),
      };

  factory Position.fromJson(Map<String, dynamic> json) => Position(
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
        accuracy: (json['acc'] as num?)?.toDouble(),
        heading: (json['hdg'] as num?)?.toDouble(),
        rssiDistance: (json['rd'] as num?)?.toDouble(),
        rssi: json['rssi'] as int?,
        headingConfidence: (json['hc'] as num?)?.toDouble(),
        tilt: (json['tilt'] as num?)?.toDouble(),
        steps: (json['st'] as num?)?.toInt(),
        cadence: (json['cad'] as num?)?.toDouble(),
        motion: json['mo'] as String?,
        deadReckoned: (json['dr'] as bool?) ?? false,
        timestamp: DateTime.parse(json['ts'] as String),
      );

  Position copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    double? heading,
    double? rssiDistance,
    int? rssi,
    DateTime? timestamp,
    double? headingConfidence,
    double? tilt,
    int? steps,
    double? cadence,
    String? motion,
    bool? deadReckoned,
  }) {
    return Position(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      rssiDistance: rssiDistance ?? this.rssiDistance,
      rssi: rssi ?? this.rssi,
      timestamp: timestamp ?? this.timestamp,
      headingConfidence: headingConfidence ?? this.headingConfidence,
      tilt: tilt ?? this.tilt,
      steps: steps ?? this.steps,
      cadence: cadence ?? this.cadence,
      motion: motion ?? this.motion,
      deadReckoned: deadReckoned ?? this.deadReckoned,
    );
  }
}
