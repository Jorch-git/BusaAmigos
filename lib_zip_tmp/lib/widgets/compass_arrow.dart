import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme/app_theme.dart';

/// Flecha grande verde que apunta hacia el miembro seleccionado.
/// El ángulo se calcula como `bearing - heading` afuera del widget.
class CompassArrow extends StatelessWidget {
  /// Ángulo en grados, donde 0 = el objetivo está justo al frente del usuario.
  final double angleDegrees;

  /// Si la dirección es confiable. Si no (ej. brújula no calibrada o GPS pobre),
  /// pintamos la flecha más tenue.
  final bool reliable;

  const CompassArrow({
    super.key,
    required this.angleDegrees,
    this.reliable = true,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _CompassPainter(
          angle: angleDegrees * math.pi / 180,
          reliable: reliable,
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double angle;
  final bool reliable;

  _CompassPainter({required this.angle, required this.reliable});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2 - 8;

    // Anillos de fondo.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.radarGrid;
    canvas.drawCircle(center, outerR, ringPaint);
    canvas.drawCircle(center, outerR * 0.66, ringPaint);
    canvas.drawCircle(center, outerR * 0.33, ringPaint);

    // Flecha
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final arrowColor = reliable
        ? AppTheme.accentGreen
        : AppTheme.textMuted;

    final arrowPaint = Paint()..color = arrowColor;
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
      old.angle != angle || old.reliable != reliable;
}
