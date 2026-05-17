/// Representa la posición conocida de un miembro.
///
/// Hay dos fuentes posibles:
///  - GPS real (lat/lng + accuracy): la fuente principal cuando hay señal.
///  - RSSI BLE (rssiDistance): fallback cuando solo nos llegamos por mesh
///    local sin GPS, o complemento para refinar a corta distancia.
///
/// Si las dos están disponibles, [GroupController] elige la de menor error
/// estimado (típicamente GPS pasados los ~5 m, RSSI por debajo).
class Position {
  /// Coordenadas geográficas. `null` si solo tenemos RSSI.
  final double? latitude;
  final double? longitude;

  /// Precisión horizontal del GPS en metros. Cuanto menor, mejor.
  final double? accuracy;

  /// Rumbo del miembro en grados (0 = norte, 90 = este). Solo cuando se mueve.
  final double? heading;

  /// Distancia estimada por RSSI BLE en metros. `null` si no hay medición.
  final double? rssiDistance;

  /// RSSI bruto de la última medición BLE, en dBm. Útil para calidad.
  final int? rssi;

  /// Cuándo se midió esta posición.
  final DateTime timestamp;

  const Position({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.heading,
    this.rssiDistance,
    this.rssi,
    required this.timestamp,
  });

  bool get hasGps => latitude != null && longitude != null;
  bool get hasRssi => rssiDistance != null;

  /// Tiempo transcurrido desde la última medición.
  Duration get age => DateTime.now().difference(timestamp);

  /// Considera la posición "fresca" si tiene menos de 30 s.
  bool get isFresh => age.inSeconds < 30;

  Map<String, dynamic> toJson() => {
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (accuracy != null) 'acc': accuracy,
        if (heading != null) 'hdg': heading,
        if (rssiDistance != null) 'rd': rssiDistance,
        if (rssi != null) 'rssi': rssi,
        'ts': timestamp.toUtc().toIso8601String(),
      };

  factory Position.fromJson(Map<String, dynamic> json) => Position(
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
        accuracy: (json['acc'] as num?)?.toDouble(),
        heading: (json['hdg'] as num?)?.toDouble(),
        rssiDistance: (json['rd'] as num?)?.toDouble(),
        rssi: json['rssi'] as int?,
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
  }) {
    return Position(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      rssiDistance: rssiDistance ?? this.rssiDistance,
      rssi: rssi ?? this.rssi,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
