import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme/app_theme.dart';

/// Flecha que apunta hacia el miembro seleccionado.
///
/// Mejoras sobre la versión previa:
///  - **Animación por arco corto.** Interpola el giro tomando siempre el
///    camino más corto del círculo (no salta de 359° a 0°).
///  - **Confianza visual.** La opacidad/color reflejan qué tan fiable es la
///    dirección (combina rumbo poco confiable + GPS pobre).
///
/// El ángulo se sigue calculando afuera como `bearing - heading`, pero ahora
/// el `heading` viene del filtro complementario, así que entra mucho más
/// estable.
class CompassArrow extends StatelessWidget {
  /// Ángulo en grados: 0 = el objetivo está justo al frente.
  final double angleDegrees;

  /// Confianza [0..1] de la dirección. <0.5 la pinta tenue.
  final double confidence;

  const CompassArrow({
    super.key,
    required this.angleDegrees,
    this.confidence = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final target = angleDegrees * math.pi / 180;
    return AspectRatio(
      aspectRatio: 1,
      child: TweenAnimationBuilder<double>(
        // El tween se actualiza con el ángulo objetivo; el builder se encarga
        // de animar suavemente desde el valor previo por el arco más corto.
        tween: _ShortestAngleTween(end: target),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (_, value, __) => CustomPaint(
          painter: _CompassPainter(angle: value, confidence: confidence),
        ),
      ),
    );
  }
}

/// Tween que interpola ángulos (radianes) por el arco más corto, evitando el
/// "giro largo" cuando se cruza el 0/2π.
class _ShortestAngleTween extends Tween<double> {
  _ShortestAngleTween({required double end}) : super(end: end);

  @override
  double lerp(double t) {
    final b = begin ?? end ?? 0;
    final e = end ?? 0;
    var delta = (e - b) % (2 * math.pi);
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    return b + delta * t;
  }
}

class _CompassPainter extends CustomPainter {
  final double angle;
  final double confidence;

  _CompassPainter({required this.angle, required this.confidence});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2 - 8;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.radarGrid;
    canvas.drawCircle(center, outerR, ringPaint);
    canvas.drawCircle(center, outerR * 0.66, ringPaint);
    canvas.drawCircle(center, outerR * 0.33, ringPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Color/opacidad según confianza: verde sólido cuando es fiable, gris y
    // tenue cuando no.
    final reliable = confidence >= 0.5;
    final base = reliable ? AppTheme.accentGreen : AppTheme.textMuted;
    final opacity = (0.45 + 0.55 * confidence).clamp(0.3, 1.0);
    final arrowPaint = Paint()..color = base.withValues(alpha: opacity);

    final path = Path()
      ..moveTo(0, -outerR * 0.78)
      ..lineTo(outerR * 0.32, 0)
      ..lineTo(outerR * 0.10, 0)
      ..lineTo(outerR * 0.10, outerR * 0.55)
      ..lineTo(-outerR * 0.10, outerR * 0.55)
      ..lineTo(-outerR * 0.10, 0)
      ..lineTo(-outerR * 0.32, 0)
      ..close();
    canvas.drawPath(path, arrowPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.angle != angle || old.confidence != confidence;
}
