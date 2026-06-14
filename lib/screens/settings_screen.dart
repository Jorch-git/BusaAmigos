import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../config/theme/theme_controller.dart';
import '../services/group_controller.dart';
import '../services/logging/event_log_service.dart';
import 'event_log_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final log = context.watch<EventLogService>();
    final theme = context.watch<ThemeController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: SafeArea(
        child: ListView(
          children: [
            _section(context, 'Apariencia', icon: Icons.palette_outlined),
            // Toggle de tema claro/oscuro.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppTheme.cardBgOf(context))),
              ),
              child: Row(
                children: [
                  Icon(
                    theme.isDark ? Icons.dark_mode : Icons.light_mode,
                    color: AppTheme.accentGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Tema oscuro', style: TextStyle(fontSize: 15)),
                  ),
                  Switch(
                    value: theme.isDark,
                    activeThumbColor: AppTheme.accentGreen,
                    onChanged: (_) => theme.toggle(),
                  ),
                ],
              ),
            ),

            _section(context, 'Perfil', icon: Icons.person_outline),
            _row(context, 'Nombre y avatar',
                trailing: controller.group?.self?.displayName ?? '-'),
            _row(context, 'Información médica', trailing: 'Configurar'),

            _section(context, 'Privacidad', icon: Icons.lock_outline),
            FutureBuilder<String>(
              future: controller.crypto?.fingerprint() ?? Future.value('-'),
              builder: (_, snap) => _row(
                context,
                'Cifrado end-to-end',
                trailing: snap.data == null ? '-' : 'Activo · ${snap.data}',
                trailingColor: AppTheme.accentGreen,
              ),
            ),
            _row(context, 'Borrado automático', trailing: '7 días'),

            _section(context, 'Ahorro de batería', icon: Icons.battery_saver),
            _row(context, 'Modo de energía', trailing: 'Balanceado'),
            _row(context, 'Escaneo Bluetooth', trailing: 'Normal'),

            _section(context, 'Desarrollo', icon: Icons.bug_report_outlined),
            _row(
              context,
              'Registro de la sesión',
              trailing: '${log.count} eventos',
              trailingColor: AppTheme.accentGreen,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EventLogScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, {required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentGreen, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: AppTheme.accentGreen,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String title,
      {required String trailing, Color? trailingColor, VoidCallback? onTap}) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppTheme.cardBgOf(context))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          Text(trailing,
              style: TextStyle(
                color: trailingColor ?? AppTheme.textMutedOf(context),
                fontSize: 13,
                fontWeight:
                    trailingColor != null ? FontWeight.w600 : FontWeight.normal,
              )),
          Icon(Icons.chevron_right,
              color: AppTheme.textMutedOf(context), size: 20),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
