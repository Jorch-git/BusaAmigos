import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'beacon_config.dart';
import 'imu_types.dart';

/// Núcleo del rastreo "con esteroides". Combina acelerómetro (con y sin
/// gravedad), giroscopio y magnetómetro para producir un [MotionSnapshot]
/// continuo, que es lo que alimenta el radar, la flecha de la brújula y el
/// beacon.
///
/// Tres cálculos clave, todos en Dart puro (sin nativo):
///
///  1. **Rumbo (heading) fusionado.** El magnetómetro da un rumbo ABSOLUTO
///     pero ruidoso (y se ensucia cerca de metal/bocinas de un escenario);
///     el giroscopio da cambios SUAVES pero acumula drift. Un filtro
///     complementario mezcla ambos: el giroscopio manda en el corto plazo
///     (suavidad de la flecha) y el magnetómetro corrige el drift en el
///     largo plazo. El rumbo magnético se compensa por inclinación con el
///     acelerómetro, para que funcione aunque el teléfono no esté plano.
///
///  2. **Detección de pasos.** Sobre la magnitud de la aceleración lineal
///     (sin gravedad) se aplica un suavizado y una detección de picos con
///     histéresis y tiempo refractario. Cada pico = un paso.
///
///  3. **Dead reckoning.** En cada paso se avanza una zancada en la
///     dirección del rumbo fusionado. Esto rellena el hueco entre fixes de
///     GPS (útil en festivales donde el GPS es pobre). El acumulado
///     (drNorth, drEast) se resetea cuando llega un GPS bueno (anclaje).
///
/// El servicio NO conoce el GPS directamente: el [GroupController] le avisa
/// de un anclaje con [anchorToGps] cuando recibe un fix confiable.
class SensorFusionService {
  SensorFusionService({BeaconConfig? config})
      : _config = config ?? const BeaconConfig();

  BeaconConfig _config;
  BeaconConfig get config => _config;
  set config(BeaconConfig c) {
    _config = c;
    if (_running) {
      // Re-suscribir con el nuevo periodo de muestreo.
      _restartSensorStreams();
    }
  }

  // ---- Streams de salida ----
  final _snapshotCtrl = StreamController<MotionSnapshot>.broadcast();
  Stream<MotionSnapshot> get snapshotStream => _snapshotCtrl.stream;

  MotionSnapshot _last = MotionSnapshot.zero();
  MotionSnapshot get lastSnapshot => _last;

  // ---- Suscripciones ----
  StreamSubscription? _accSub, _userAccSub, _gyroSub, _magSub;
  Timer? _emitTimer;
  bool _running = false;

  // ---- Estado de fusión ----
  ImuSample _imu = const ImuSample();

  double _heading = 0; // rumbo fusionado actual (grados, 0..360)
  bool _headingInitialized = false;
  DateTime? _lastGyroTs;

  // Detección de pasos
  double _lpMag = 0; // magnitud lineal suavizada
  double _peakMin = double.infinity, _peakMax = -double.infinity;
  bool _aboveThreshold = false;
  DateTime _lastStepTs = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _recentSteps = [];
  int _stepCount = 0;

  // Dead reckoning
  double _drNorth = 0, _drEast = 0;

  // ---- Parámetros de detección (calibrables) ----
  /// Constante de Weinberg para estimar longitud de zancada a partir de la
  /// amplitud de aceleración del paso. ~0.4–0.5 funciona para la mayoría.
  static const double _weinbergK = 0.46;

  /// Umbral de magnitud lineal (m/s^2) para considerar un pico de paso.
  static const double _stepThreshold = 1.2;

  /// Tiempo mínimo entre pasos (evita doble conteo). 250 ms => máx 4 pasos/s.
  static const Duration _stepRefractory = Duration(milliseconds: 250);

  /// Peso del giroscopio en el filtro complementario. Alto = más suave pero
  /// confía más en el gyro (más drift); el resto lo aporta el magnetómetro.
  static const double _gyroWeight = 0.98;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _subscribeSensors();
    // Emisión periódica del snapshot al ritmo configurado del beacon.
    _emitTimer = Timer.periodic(_config.beaconInterval, (_) => _emit());
    debugPrint('SensorFusionService: iniciado (beacon=${_config.beaconInterval.inMilliseconds}ms)');
  }

  Future<void> stop() async {
    _running = false;
    await _accSub?.cancel();
    await _userAccSub?.cancel();
    await _gyroSub?.cancel();
    await _magSub?.cancel();
    _accSub = _userAccSub = _gyroSub = _magSub = null;
    _emitTimer?.cancel();
    _emitTimer = null;
  }

  void dispose() {
    stop();
    _snapshotCtrl.close();
  }

  void _restartSensorStreams() {
    _accSub?.cancel();
    _userAccSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _subscribeSensors();
    _emitTimer?.cancel();
    _emitTimer = Timer.periodic(_config.beaconInterval, (_) => _emit());
  }

  void _subscribeSensors() {
    final period = _config.sensorSamplingPeriod;

    _accSub = accelerometerEventStream(samplingPeriod: period).listen(
      (e) => _imu = _imu.copyWith(ax: e.x, ay: e.y, az: e.z),
      onError: (e) => debugPrint('SensorFusion: acc error $e'),
      cancelOnError: false,
    );

    _userAccSub = userAccelerometerEventStream(samplingPeriod: period).listen(
      (e) {
        _imu = _imu.copyWith(lax: e.x, lay: e.y, laz: e.z);
        _processStep();
      },
      onError: (e) => debugPrint('SensorFusion: userAcc error $e'),
      cancelOnError: false,
    );

    _gyroSub = gyroscopeEventStream(samplingPeriod: period).listen(
      (e) {
        _imu = _imu.copyWith(gx: e.x, gy: e.y, gz: e.z);
        _integrateGyro();
      },
      onError: (e) => debugPrint('SensorFusion: gyro error $e'),
      cancelOnError: false,
    );

    _magSub = magnetometerEventStream(samplingPeriod: period).listen(
      (e) => _imu = _imu.copyWith(mx: e.x, my: e.y, mz: e.z),
      onError: (e) => debugPrint('SensorFusion: mag error $e'),
      cancelOnError: false,
    );
  }

  // ---- Cálculo de inclinación (roll/pitch) desde el acelerómetro ----

  /// Roll (alrededor del eje Y) en radianes.
  double get _roll => math.atan2(_imu.ay, _imu.az);

  /// Pitch (alrededor del eje X) en radianes.
  double get _pitch =>
      math.atan2(-_imu.ax, math.sqrt(_imu.ay * _imu.ay + _imu.az * _imu.az));

  /// Inclinación total respecto a la horizontal, en grados (0 = plano).
  double get _tiltDeg {
    final g = math.sqrt(_imu.ax * _imu.ax + _imu.ay * _imu.ay + _imu.az * _imu.az);
    if (g == 0) return 0;
    // Ángulo entre el eje Z del teléfono y la vertical real.
    final cosT = (_imu.az / g).clamp(-1.0, 1.0);
    return _rad2deg(math.acos(cosT.abs()));
  }

  /// Rumbo magnético ABSOLUTO, compensado por inclinación. Grados 0..360.
  double _tiltCompensatedHeading() {
    final phi = _roll;
    final theta = _pitch;
    final mx = _imu.mx, my = _imu.my, mz = _imu.mz;

    // Proyecta el campo magnético al plano horizontal usando roll/pitch.
    final xh = mx * math.cos(theta) +
        my * math.sin(theta) * math.sin(phi) +
        mz * math.sin(theta) * math.cos(phi);
    final yh = my * math.cos(phi) - mz * math.sin(phi);

    var heading = _rad2deg(math.atan2(-yh, xh));
    if (heading < 0) heading += 360;
    return heading;
  }

  /// Confianza del rumbo [0..1]. Penaliza dos cosas:
  ///  - Campo magnético fuera del rango terrestre (~25–65 µT) => interferencia.
  ///  - Inclinación extrema del teléfono (lectura poco fiable).
  double _headingConfidence() {
    final bMag = math.sqrt(_imu.mx * _imu.mx + _imu.my * _imu.my + _imu.mz * _imu.mz);
    double magScore;
    if (bMag < 20 || bMag > 70) {
      magScore = 0.2; // probablemente perturbado
    } else if (bMag < 25 || bMag > 65) {
      magScore = 0.6;
    } else {
      magScore = 1.0;
    }
    final tilt = _tiltDeg;
    final tiltScore = tilt > 60 ? 0.4 : (tilt > 35 ? 0.7 : 1.0);
    return (magScore * tiltScore).clamp(0.0, 1.0);
  }

  // ---- Filtro complementario del rumbo ----

  void _integrateGyro() {
    final now = DateTime.now();
    final last = _lastGyroTs;
    _lastGyroTs = now;

    final headingAbs = _tiltCompensatedHeading();

    if (!_headingInitialized) {
      _heading = headingAbs;
      _headingInitialized = true;
      return;
    }

    if (last == null) return;
    final dt = now.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.5) return; // descarta saltos raros

    // Tasa de cambio de yaw aproximada. Cuando el teléfono está casi
    // horizontal, la rotación en el mundo ~ -gz. Para inclinaciones grandes
    // proyectamos por roll/pitch (aproximación de primer orden suficiente
    // para suavizar entre correcciones del magnetómetro).
    final phi = _roll, theta = _pitch;
    final yawRate = -(_imu.gz * math.cos(phi) * math.cos(theta) +
        _imu.gy * math.sin(phi) - _imu.gx * math.cos(phi) * math.sin(theta));

    final predicted = _wrap360(_heading + _rad2deg(yawRate * dt));

    // Confianza del magnetómetro decide cuánto corregimos hacia el absoluto.
    final conf = _headingConfidence();
    final magWeight = (1 - _gyroWeight) * conf;
    _heading = _blendAngles(predicted, headingAbs, magWeight);
  }

  // ---- Detección de pasos + dead reckoning ----

  void _processStep() {
    final mag = _imu.linearMagnitude;
    // Suavizado exponencial para quitar ruido de alta frecuencia.
    _lpMag = _lpMag == 0 ? mag : (0.7 * _lpMag + 0.3 * mag);

    final now = DateTime.now();

    if (_lpMag > _stepThreshold) {
      _aboveThreshold = true;
      if (_lpMag > _peakMax) _peakMax = _lpMag;
      if (_lpMag < _peakMin) _peakMin = _lpMag;
    } else if (_aboveThreshold) {
      // Caímos por debajo del umbral: cierre de un pico => candidato a paso.
      _aboveThreshold = false;
      if (now.difference(_lastStepTs) >= _stepRefractory) {
        _registerStep(now);
      }
      _peakMin = double.infinity;
      _peakMax = -double.infinity;
    }
  }

  void _registerStep(DateTime now) {
    _lastStepTs = now;
    _stepCount++;

    // Longitud de zancada (Weinberg): L = K * (amax - amin)^(1/4).
    double stride;
    if (_config.useFixedStride) {
      stride = _config.fixedStrideMeters;
    } else {
      final amp = (_peakMax - _peakMin).clamp(0.0, 50.0);
      stride = (_weinbergK * math.pow(amp, 0.25)).toDouble();
      // Acotar a un rango humano sensato.
      stride = stride.clamp(0.3, 1.0);
    }

    final hRad = _deg2rad(_heading);
    _drNorth += stride * math.cos(hRad);
    _drEast += stride * math.sin(hRad);

    _recentSteps.add(now);
    _recentSteps.removeWhere((t) => now.difference(t) > const Duration(seconds: 5));
  }

  MotionState _motionState(double cadence) {
    if (cadence < 5) return MotionState.still;
    if (cadence < 130) return MotionState.walking;
    return MotionState.running;
  }

  double _cadence() {
    if (_recentSteps.length < 2) return 0;
    final span = _recentSteps.last.difference(_recentSteps.first).inMilliseconds;
    if (span <= 0) return 0;
    return (_recentSteps.length - 1) / (span / 60000.0); // pasos/min
  }

  /// El [GroupController] llama esto cuando recibe un GPS confiable. Resetea
  /// el dead reckoning para que el error acumulado no crezca sin límite.
  void anchorToGps() {
    _drNorth = 0;
    _drEast = 0;
  }

  /// Permite inyectar un rumbo absoluto externo (p. ej. el de FlutterCompass,
  /// que en algunos equipos viene mejor calibrado). Se fusiona como una
  /// corrección suave hacia ese valor.
  void feedExternalHeading(double headingDeg, {double weight = 0.1}) {
    if (!_headingInitialized) {
      _heading = _wrap360(headingDeg);
      _headingInitialized = true;
      return;
    }
    _heading = _blendAngles(_heading, _wrap360(headingDeg), weight);
  }

  void _emit() {
    if (!_running) return;
    final cadence = _cadence();
    _last = MotionSnapshot(
      headingDeg: _wrap360(_heading),
      headingConfidence: _headingConfidence(),
      tiltDeg: _tiltDeg,
      motion: _motionState(cadence),
      stepCount: _stepCount,
      cadence: cadence,
      drNorth: _drNorth,
      drEast: _drEast,
      timestamp: DateTime.now(),
    );
    if (!_snapshotCtrl.isClosed) _snapshotCtrl.add(_last);
  }

  // ---- Utilidades angulares ----

  static double _rad2deg(double r) => r * 180 / math.pi;
  static double _deg2rad(double d) => d * math.pi / 180;
  static double _wrap360(double d) => ((d % 360) + 360) % 360;

  /// Mezcla dos ángulos (grados) respetando el círculo: interpola por el
  /// arco más corto. [w] es el peso del segundo ángulo [b].
  static double _blendAngles(double a, double b, double w) {
    final ar = _deg2rad(a), br = _deg2rad(b);
    final x = math.cos(ar) * (1 - w) + math.cos(br) * w;
    final y = math.sin(ar) * (1 - w) + math.sin(br) * w;
    return _wrap360(_rad2deg(math.atan2(y, x)));
  }
}
