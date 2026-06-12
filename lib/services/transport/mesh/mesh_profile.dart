/// Perfil de propagación del mesh. Equivale a los "propagation profiles" de
/// Bridgefy, pero aquí es código tuyo y lo puedes ajustar a discreción.
///
/// Los parámetros controlan el equilibrio entre ALCANCE (que el mensaje llegue
/// lejos) y RUIDO (no inundar la red con reenvíos redundantes). En multitudes
/// densas conviene MENOS TTL y reenvío probabilístico (gossip) para evitar
/// tormentas de broadcast; en zonas dispersas conviene MÁS TTL.
class MeshProfile {
  /// Saltos máximos que puede dar un mensaje (TTL inicial). Cada reenvío resta 1.
  final int ttl;

  /// Cuánto tiempo recordamos un id de mensaje ya visto (para dedupe).
  final Duration seenTtl;

  /// Tope de ids recordados (evita crecer sin límite; expulsa los más viejos).
  final int maxSeen;

  /// Retardo aleatorio máximo antes de reenviar. Desincroniza a los nodos para
  /// que no reboten todos a la vez (clave para estabilidad en multitudes).
  final int rebroadcastJitterMs;

  /// Probabilidad de reenviar cada mensaje [0..1]. <1 implementa "gossip":
  /// en una multitud densa, si cada quien reenvía solo a veces, el mensaje
  /// igual se propaga (hay redundancia de sobra) pero con MUCHO menos ruido.
  final double forwardProbability;

  /// Nombre legible para la UI/consola.
  final String name;

  const MeshProfile({
    required this.name,
    required this.ttl,
    required this.seenTtl,
    required this.maxSeen,
    required this.rebroadcastJitterMs,
    required this.forwardProbability,
  });

  /// Equilibrado, uso general.
  static const standard = MeshProfile(
    name: 'standard',
    ttl: 5,
    seenTtl: Duration(minutes: 2),
    maxSeen: 4000,
    rebroadcastJitterMs: 120,
    forwardProbability: 1.0,
  );

  /// Multitudes densas (conciertos, estadios): TTL moderado, jitter alto y
  /// gossip para no saturar el aire BLE/Wi-Fi.
  static const highDensity = MeshProfile(
    name: 'highDensity',
    ttl: 4,
    seenTtl: Duration(minutes: 3),
    maxSeen: 8000,
    rebroadcastJitterMs: 250,
    forwardProbability: 0.65,
  );

  /// Zonas dispersas: pocos nodos, hay que estirar el alcance. TTL alto y
  /// reenvío seguro.
  static const sparse = MeshProfile(
    name: 'sparse',
    ttl: 8,
    seenTtl: Duration(minutes: 5),
    maxSeen: 2000,
    rebroadcastJitterMs: 80,
    forwardProbability: 1.0,
  );

  /// Máximo alcance a costa de más tráfico.
  static const longReach = MeshProfile(
    name: 'longReach',
    ttl: 12,
    seenTtl: Duration(minutes: 6),
    maxSeen: 3000,
    rebroadcastJitterMs: 100,
    forwardProbability: 1.0,
  );

  MeshProfile copyWith({
    String? name,
    int? ttl,
    Duration? seenTtl,
    int? maxSeen,
    int? rebroadcastJitterMs,
    double? forwardProbability,
  }) {
    return MeshProfile(
      name: name ?? this.name,
      ttl: ttl ?? this.ttl,
      seenTtl: seenTtl ?? this.seenTtl,
      maxSeen: maxSeen ?? this.maxSeen,
      rebroadcastJitterMs: rebroadcastJitterMs ?? this.rebroadcastJitterMs,
      forwardProbability: forwardProbability ?? this.forwardProbability,
    );
  }
}
