import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../services/group_controller.dart';
import '../utils/distance_calculator.dart';
import '../widgets/compass_arrow.dart';

class CompassScreen extends StatelessWidget {
  final String targetMemberId;

  const CompassScreen({super.key, required this.targetMemberId});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) return const Scaffold();

    final target = group.members.firstWhere(
      (m) => m.id == targetMemberId,
      orElse: () => group.self!,
    );

    final selfPos = group.self?.lastPosition;
    final result = DistanceCalculator.between(selfPos, target.lastPosition);

    final heading = controller.selfHeading ?? 0;
    final relativeAngle = result.bearing != null
        ? (result.bearing! - heading + 360) % 360
        : 0.0;

    final reliable = result.source == DistanceSource.gps &&
        (result.errorMeters ?? 999) < 15;

    return Scaffold(
      appBar: AppBar(
        title: Text('Buscando a ${target.displayName}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: CompassArrow(
                      angleDegrees: relativeAngle,
                      reliable: reliable,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (result.source != DistanceSource.none)
                Column(
                  children: [
                    Text(
                      '~${result.meters.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text('metros',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ],
                )
              else
                const Text(
                  'Sin posición todavía',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              const SizedBox(height: 24),
              if (result.errorMeters != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gps_fixed,
                          size: 18, color: AppTheme.accentGreen),
                      const SizedBox(width: 8),
                      const Text('Precisión GPS',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        '±${result.errorMeters!.toStringAsFixed(0)} m',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Llamar atención'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF378ADD),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // En el video llama la atención del miembro objetivo:
                    // se manda un mensaje de chat con un emoji distintivo.
                    controller.sendChat('👋 ${target.displayName}, ¡por aquí!');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Aviso enviado a ${target.displayName}')),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.textMuted),
                  ),
                  child: const Text('Volver al radar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
