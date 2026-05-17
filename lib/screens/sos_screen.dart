import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../models/sos_alert.dart';
import '../services/group_controller.dart';

class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final alert = controller.activeSos;
    final group = controller.group;
    if (alert == null || group == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const Scaffold();
    }

    final isMine = group.self?.id == alert.triggeredBy;

    return Scaffold(
      backgroundColor: AppTheme.sosRed.withValues(alpha: 0.15),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppTheme.sosRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'ALERTA DE EMERGENCIA',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              Text(
                isMine ? 'ACTIVADA' : 'POR ${alert.triggeredByName.toUpperCase()}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                isMine
                    ? 'Tus amigos han sido notificados'
                    : '${alert.triggeredByName} necesita ayuda',
                style: const TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: group.others.map((m) {
                    final response =
                        alert.responses[m.id] ?? SosResponse.pending;
                    final distance = alert.distanceAtResponse[m.id];
                    return _buildResponderTile(m.displayName, response, distance);
                  }).toList(),
                ),
              ),
              if (isMine)
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Ayuda recibida'),
                  onPressed: () async {
                    await controller.dismissSos();
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                  ),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.directions_run),
                        label: const Text('Voy en camino'),
                        onPressed: () => controller
                            .respondToSos(SosResponse.onTheWay),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: AppTheme.accentGreen,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () =>
                            controller.respondToSos(SosResponse.cantHelp),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: AppTheme.textMuted,
                          side: const BorderSide(color: AppTheme.textMuted),
                        ),
                        child: const Text('No puedo ayudar'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponderTile(
      String name, SosResponse response, double? distance) {
    final IconData icon;
    final Color color;
    final String label;
    switch (response) {
      case SosResponse.pending:
        icon = Icons.access_time;
        color = AppTheme.textMuted;
        label = 'Sin respuesta';
      case SosResponse.onTheWay:
        icon = Icons.directions_run;
        color = AppTheme.accentGreen;
        label = distance != null
            ? 'En camino (a ${distance.toStringAsFixed(0)} m)'
            : 'En camino';
      case SosResponse.arrived:
        icon = Icons.check_circle;
        color = AppTheme.accentGreen;
        label = 'Llegó';
      case SosResponse.cantHelp:
        icon = Icons.cancel;
        color = AppTheme.sosRed;
        label = 'No puede ayudar';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
