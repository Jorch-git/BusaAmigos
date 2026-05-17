/// Estado de respuesta de un miembro a un SOS activo.
enum SosResponse {
  /// Aún no respondió.
  pending,

  /// Confirmó que va al rescate.
  onTheWay,

  /// Llegó al lugar.
  arrived,

  /// Indicó que no puede ayudar (lejos, otro problema, etc.).
  cantHelp,
}

/// Alerta SOS activa. Una sola por grupo a la vez.
class SosAlert {
  /// Quién disparó el SOS.
  final String triggeredBy;
  final String triggeredByName;
  final DateTime triggeredAt;

  /// Respuestas de cada miembro: memberId -> SosResponse.
  final Map<String, SosResponse> responses;

  /// Distancia estimada de cada respondedor en el momento de responder.
  /// memberId -> metros aprox.
  final Map<String, double> distanceAtResponse;

  const SosAlert({
    required this.triggeredBy,
    required this.triggeredByName,
    required this.triggeredAt,
    this.responses = const {},
    this.distanceAtResponse = const {},
  });

  Duration get age => DateTime.now().difference(triggeredAt);

  SosAlert withResponse(
    String memberId,
    SosResponse response, {
    double? distance,
  }) {
    return SosAlert(
      triggeredBy: triggeredBy,
      triggeredByName: triggeredByName,
      triggeredAt: triggeredAt,
      responses: {...responses, memberId: response},
      distanceAtResponse: distance != null
          ? {...distanceAtResponse, memberId: distance}
          : distanceAtResponse,
    );
  }

  Map<String, dynamic> toJson() => {
        'by': triggeredBy,
        'byName': triggeredByName,
        'at': triggeredAt.toUtc().toIso8601String(),
        'responses': responses.map((k, v) => MapEntry(k, v.name)),
        'distances': distanceAtResponse,
      };

  factory SosAlert.fromJson(Map<String, dynamic> json) => SosAlert(
        triggeredBy: json['by'] as String,
        triggeredByName: json['byName'] as String,
        triggeredAt: DateTime.parse(json['at'] as String),
        responses: (json['responses'] as Map? ?? {}).map(
          (k, v) => MapEntry(
            k as String,
            SosResponse.values.firstWhere(
              (e) => e.name == v,
              orElse: () => SosResponse.pending,
            ),
          ),
        ),
        distanceAtResponse: (json['distances'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      );
}
