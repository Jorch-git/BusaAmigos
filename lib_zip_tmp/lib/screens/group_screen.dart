import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../models/member.dart';
import '../services/group_controller.dart';
import '../utils/distance_calculator.dart';
import 'compass_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'share_qr_screen.dart';

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) return const SizedBox();

    final selfPos = group.self?.lastPosition;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(group.code,
                        style: const TextStyle(
                          color: AppTheme.accentGreen,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        )),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: group.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado')),
                  );
                },
                tooltip: 'Copiar código',
              ),
              IconButton(
                icon: const Icon(Icons.qr_code, size: 22),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShareQrScreen()),
                ),
                tooltip: 'Mostrar QR para invitar',
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
        ),
        // Banda destacada de "Invitar" para que sea muy visible que se puede
        // volver a compartir el QR aunque ya esté creado el grupo.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShareQrScreen()),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accentGreen.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner,
                      color: AppTheme.accentGreen, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Invitar a más amigos',
                            style: TextStyle(
                              color: AppTheme.accentGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            )),
                        SizedBox(height: 2),
                        Text('Mostrar QR y ver quién está confirmado',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: AppTheme.accentGreen, size: 20),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final m in group.members)
                _buildTile(context, m, selfPos, controller),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.exit_to_app, color: AppTheme.sosRed),
                label: const Text('Salir del grupo',
                    style: TextStyle(color: AppTheme.sosRed)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: AppTheme.sosRed),
                ),
                onPressed: () async {
                  await controller.leaveGroup();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (_) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context,
    Member m,
    selfPos,
    GroupController controller,
  ) {
    final result = m.isSelf
        ? null
        : DistanceCalculator.between(selfPos, m.lastPosition);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(m.colorSeed),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    m.displayName.isNotEmpty
                        ? m.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // Punto de estado indicando si está confirmado/cerca.
              if (!m.isSelf)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _statusDotColor(m.status),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.cardBg, width: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(m.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  if (m.isSelf) ...[
                    const SizedBox(width: 6),
                    const Text('(tú)',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  _statusLabel(m, result),
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!m.isSelf && result?.source != DistanceSource.none)
            IconButton(
              icon: const Icon(Icons.navigation_outlined,
                  color: AppTheme.accentGreen),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CompassScreen(targetMemberId: m.id)),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusDotColor(MemberStatus status) {
    switch (status) {
      case MemberStatus.online:
        return AppTheme.accentGreen;
      case MemberStatus.stale:
        return const Color(0xFFEEC42E);
      case MemberStatus.offline:
        return AppTheme.textMuted;
    }
  }

  String _statusLabel(Member m, DistanceResult? r) {
    if (m.isSelf) return 'Tu posición';
    switch (m.status) {
      case MemberStatus.online:
        if (r?.source == DistanceSource.gps) {
          return 'Confirmado · ~${r!.meters.toStringAsFixed(0)} m';
        }
        return 'Confirmado';
      case MemberStatus.stale:
        return 'Última señal hace ${m.lastPosition?.age.inSeconds ?? 0} s';
      case MemberStatus.offline:
        return 'Sin señal';
    }
  }
}
