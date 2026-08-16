import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme/app_theme.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/position.dart';
import '../services/ble/ble_proximity_service.dart';
import '../utils/distance_calculator.dart';

/// El radar circular del video: tres anillos concéntricos (10/50/100 m por
/// defecto), cardinales N/S/E/W, miembros pintados como puntos según su
/// posición real en relación al usuario, y el "self" como un círculo azul
/// pulsante en el centro.
class RadarWidget extends StatefulWidget {
  final Group group;
  final double? selfHeading;
  final void Function(Member member) onMemberTap;
  final double radiusMeters;

  const RadarWidget({
    super.key,
    required this.group,
    required this.onMemberTap,
    this.selfHeading,
    this.radiusMeters = 50,
  });

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        onTapUp: (details) => _handleTap(details.localPosition, Size(size, size)),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => CustomPaint(
            size: Size(size, size),
            painter: _RadarPainter(
              group: widget.group,
              radiusMeters: widget.radiusMeters,
              heading: widget.selfHeading ?? 0,
              pulseProgress: _pulse.value,
            ),
          ),
        ),
      );
    });
  }

  void _handleTap(Offset localPos, Size size) {
    final hits = _hitTestMembers(localPos, size);
    if (hits.isNotEmpty) {
      widget.onMemberTap(hits.first);
    }
  }

  List<Member> _hitTestMembers(Offset localPos, Size size) {
    final self = widget.group.self;
    final selfPos = self?.lastPosition;
    if (self == null || selfPos == null || !selfPos.hasGps) return const [];

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadiusPx = size.width / 2 - 24;
    final hits = <Member>[];

    for (final m in widget.group.others) {
      final point = _memberPoint(
        m,
        selfPos,
        center,
        maxRadiusPx,
        widget.radiusMeters,
        widget.selfHeading ?? 0,
      );
      if (point == null) continue;
      if ((point - localPos).distance < 30) hits.add(m);
    }
    return hits;
  }
}

class _RadarPainter extends CustomPainter {
  final Group group;
  final double radiusMeters;
  final double heading;
  final double pulseProgress;

  _RadarPainter({
    required this.group,
    required this.radiusMeters,
    required this.heading,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadiusPx = size.width / 2 - 24;

    _drawRings(canvas, center, maxRadiusPx);
    _drawCardinals(canvas, center, maxRadiusPx);
    _drawSelf(canvas, center);

    final selfPos = group.self?.lastPosition;
    if (selfPos == null || !selfPos.hasGps) {
      _drawWaitingMessage(canvas, size);
      return;
    }

    for (final m in group.others) {
      _drawMember(canvas, m, selfPos, center, maxRadiusPx);
    }
  }

  void _drawRings(Canvas canvas, Offset center, double maxR) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.radarGrid;

    // Tres anillos: 1/3, 2/3, 1 del radio.
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxR * i / 3, paint);
    }

    // Cruz N-S y E-W
    canvas.drawLine(
      Offset(center.dx - maxR, center.dy),
      Offset(center.dx + maxR, center.dy),
      paint..color = AppTheme.radarGrid.withValues(alpha: 0.5),
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxR),
      Offset(center.dx, center.dy + maxR),
      paint,
    );
  }

  void _drawCardinals(Canvas canvas, Offset center, double maxR) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    const style = TextStyle(
      color: AppTheme.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    // El radar está en modo "heading-up": ARRIBA es hacia donde apunta el
    // usuario, no el norte. Por eso los cardinales N/S/E/W deben ROTAR según
    // el heading para seguir señalando las direcciones reales. Un cardinal con
    // ángulo absoluto `a` (N=0, E=90, S=180, W=270) se dibuja en pantalla en
    // el ángulo (a - heading).
    final cardinals = <String, double>{'N': 0, 'E': 90, 'S': 180, 'W': 270};
    final labelRadius = maxR + 4;

    cardinals.forEach((label, absAngle) {
      final screenAngle = (absAngle - heading) % 360;
      final theta = (screenAngle - 90) * math.pi / 180;
      final pos = Offset(
        center.dx + labelRadius * math.cos(theta),
        center.dy + labelRadius * math.sin(theta),
      );
      // El norte se resalta para que sirva de referencia.
      tp.text = TextSpan(
        text: label,
        style: label == 'N'
            ? style.copyWith(
                color: AppTheme.accentGreen, fontWeight: FontWeight.w700)
            : style,
      );
      tp.layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    });

    // Marca FIJA arriba: un triángulo que indica "hacia donde apuntas tú".
    // Como el radar es heading-up, esta marca siempre está arriba y representa
    // tu frente; los miembros aparecen alrededor relativos a ella.
    final nosePaint = Paint()..color = AppTheme.accentGreen.withValues(alpha: 0.9);
    final noseY = center.dy - maxR - 16;
    final path = Path()
      ..moveTo(center.dx, noseY)
      ..lineTo(center.dx - 7, noseY - 11)
      ..lineTo(center.dx + 7, noseY - 11)
      ..close();
    canvas.drawPath(path, nosePaint);
  }

  void _drawSelf(Canvas canvas, Offset center) {
    // Halo pulsante.
    final haloRadius = 18 + 14 * pulseProgress;
    final haloOpacity = 0.4 * (1 - pulseProgress);
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()..color = const Color(0xFF378ADD).withValues(alpha: haloOpacity),
    );

    canvas.drawCircle(center, 14, Paint()..color = const Color(0xFF378ADD));
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawMember(
    Canvas canvas,
    Member member,
    Position selfPos,
    Offset center,
    double maxR,
  ) {
    final point = _memberPoint(member, selfPos, center, maxR, radiusMeters, heading);
    if (point == null) return;

    final color = Color(member.colorSeed);
    final distance = DistanceCalculator.between(selfPos, member.lastPosition,
        rssi: BleProximityService.instance.rssiForMember(member.id));

    // Sombra suave si SOS activo.
    if (member.sosActive) {
      canvas.drawCircle(
        point,
        16,
        Paint()..color = AppTheme.sosRed.withValues(alpha: 0.4),
      );
    }

    canvas.drawCircle(point, 9, Paint()..color = color);
    canvas.drawCircle(
      point,
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Etiqueta arriba: nombre, debajo: distancia.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: member.displayName,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
    tp.layout();
    tp.paint(canvas, point + Offset(-tp.width / 2, -28));

    if (distance.source != DistanceSource.none) {
      final distText = distance.labelShort;
      tp.text = TextSpan(
        text: distText,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
      );
      tp.layout();
      tp.paint(canvas, point + Offset(-tp.width / 2, 14));
    }
  }

  void _drawWaitingMessage(Canvas canvas, Size size) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )
      ..text = const TextSpan(
        text: 'Esperando señal GPS…',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
      )
      ..layout();
    tp.paint(
      canvas,
      Offset(size.width / 2 - tp.width / 2, size.height / 2 + 60),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.group != group ||
      old.radiusMeters != radiusMeters ||
      old.heading != heading ||
      old.pulseProgress != pulseProgress;
}

/// Calcula la posición pixel de un miembro relativa al centro del radar.
/// Devuelve `null` si la distancia excede el radio mostrado.
Offset? _memberPoint(
  Member member,
  Position selfPos,
  Offset center,
  double maxR,
  double radiusMeters,
  double heading,
) {
  final pos = member.lastPosition;
  if (pos == null) return null;

  // IMPORTANTE: para POSICIONAR en el radar usamos SIEMPRE distancia y bearing
  // de GPS puro (Haversine), NO la distancia fusionada con RSSI. Motivo: el
  // RSSI da magnitud pero NO dirección, así que si lo usamos para la posición,
  // varios miembros cercanos colapsan al centro sin respetar su ángulo real
  // (bug observado: se veían "juntos" en vez de en lados opuestos). El mapa
  // siempre usó lat/long puro y por eso sí los ubicaba bien. El RSSI lo usamos
  // solo para la ETIQUETA de distancia, no para la geometría.
  if (!selfPos.hasGps || !pos.hasGps) {
    // Sin GPS de ambos lados no hay dirección posible; no dibujamos el pin en
    // el radar (la brújula/lista seguirán mostrando proximidad por RSSI).
    return null;
  }

  final distMeters = DistanceCalculator.haversine(
    selfPos.latitude!, selfPos.longitude!,
    pos.latitude!, pos.longitude!,
  );
  final bearingDeg = DistanceCalculator.bearing(
    selfPos.latitude!, selfPos.longitude!,
    pos.latitude!, pos.longitude!,
  );

  final dNorm = (distMeters / radiusMeters).clamp(0.0, 1.0);
  final distancePx = dNorm * maxR;

  // Modo "heading-up": rotamos el bearing absoluto restando hacia dónde apunta
  // el usuario. Así, lo que tienes FÍSICAMENTE enfrente aparece ARRIBA en el
  // radar, y los lados coinciden con la realidad (izquierda real = izquierda
  // en el radar). Antes era "norte arriba" y por eso no cuadraba con lo que
  // veías al voltear el teléfono.
  final relBearing = (bearingDeg - heading) % 360;
  final theta = (relBearing - 90) * math.pi / 180;

  return Offset(
    center.dx + distancePx * math.cos(theta),
    center.dy + distancePx * math.sin(theta),
  );
}
