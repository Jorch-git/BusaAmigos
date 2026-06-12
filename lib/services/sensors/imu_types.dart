import 'dart:math' as math;

/// Lectura cruda de los tres sensores inerciales en un instante.
/// Se llena de forma incremental: cada sensor llega en su propio stream,
/// así que normalmente solo un campo cambia por evento y los demás
/// conservan su último valor.
class ImuSample {
  /// Aceleración CON gravedad (m/s^2). Sirve para estimar la inclinación
  /// (roll/pitch) del teléfono respecto a la vertical.
  final double ax, ay, az;

  /// Aceleración lineal SIN gravedad (m/s^2). Su magnitud es la base de la
  /// detección de pasos.
  final double lax, lay, laz;

  /// Velocidad angular (rad/s) en los tres ejes del dispositivo.
  final double gx, gy, gz;

  /// Campo magnético (microTesla) en los tres ejes del dispositivo.
  final double mx, my, mz;

  const ImuSample({
    this.ax = 0, this.ay = 0, this.az = 9.81,
    this.lax = 0, this.lay = 0, this.laz = 0,
    this.gx = 0, this.gy = 0, this.gz = 0,
    this.mx = 0, this.my = 0, this.mz = 0,
  });

  ImuSample copyWith({
    double? ax, double? ay, double? az,
    double? lax, double? lay, double? laz,
    double? gx, double? gy, double? gz,
    double? mx, double? my, double? mz,
  }) {
    return ImuSample(
      ax: ax ?? this.ax, ay: ay ?? this.ay, az: az ?? this.az,
      lax: lax ?? this.lax, lay: lay ?? this.lay, laz: laz ?? this.laz,
      gx: gx ?? this.gx, gy: gy ?? this.gy, gz: gz ?? this.gz,
      mx: mx ?? this.mx, my: my ?? this.my, mz: mz ?? this.mz,
    );
  }

  /// Magnitud de la aceleración lineal. ~0 en reposo, sube en cada zancada.
  double get linearMagnitude => math.sqrt(lax * lax + lay * lay + laz * laz);
}

/// Qué está haciendo el usuario según los sensores. Lo usamos para no
/// disparar dead reckoning cuando está quieto y para mostrarlo en el log.
enum MotionState {
  still,
  walking,
  running,
  unknown,
}

/// Resultado de la fusión en un instante: lo que la UI y el beacon consumen.
class MotionSnapshot {
  /// Rumbo fusventido (0=N, 90=E) en grados. Suavizado por filtro
  /// complementario giroscopio+magnetómetro, compensado por inclinación.
  final double headingDeg;

  /// Confianza del rumbo [0..1]. Baja cuando el magnetómetro está siendo
  /// perturbado (cerca de bocinas, estructuras metálicas de un escenario).
  final double headingConfidence;

  /// Inclinación del teléfono respecto a la horizontal, en grados.
  /// 0 = plano sobre la mesa, 90 = vertical. Útil para saber si la lectura
  /// de brújula es fiable.
  final double tiltDeg;

  /// Estado de movimiento estimado.
  final MotionState motion;

  /// Pasos contados desde que arrancó el servicio.
  final int stepCount;

  /// Cadencia instantánea (pasos/min). 0 si está quieto.
  final double cadence;

  /// Desplazamiento acumulado por dead reckoning desde el último anclaje
  /// GPS, en metros (norte, este). Se resetea al re-anclar con GPS bueno.
  final double drNorth, drEast;

  final DateTime timestamp;

  const MotionSnapshot({
    required this.headingDeg,
    required this.headingConfidence,
    required this.tiltDeg,
    required this.motion,
    required this.stepCount,
    required this.cadence,
    required this.drNorth,
    required this.drEast,
    required this.timestamp,
  });

  factory MotionSnapshot.zero() => MotionSnapshot(
        headingDeg: 0,
        headingConfidence: 0,
        tiltDeg: 0,
        motion: MotionState.unknown,
        stepCount: 0,
        cadence: 0,
        drNorth: 0,
        drEast: 0,
        timestamp: DateTime.now(),
      );
}
