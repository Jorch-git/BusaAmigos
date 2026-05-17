import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../services/group_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: SafeArea(
        child: ListView(
          children: [
            _section('Perfil', icon: Icons.person_outline),
            _row('Nombre y avatar',
                trailing: controller.group?.self?.displayName ?? '-'),
            _row('Información médica', trailing: 'Configurar'),
            _section('Privacidad', icon: Icons.lock_outline),
            FutureBuilder<String>(
              future: controller.crypto?.fingerprint() ?? Future.value('-'),
              builder: (_, snap) => _row(
                'Cifrado end-to-end',
                trailing: snap.data == null ? '-' : 'Activo · ${snap.data}',
                trailingColor: AppTheme.accentGreen,
              ),
            ),
            _row('Borrado automático', trailing: '7 días'),
            _section('Ahorro de batería', icon: Icons.battery_saver),
            _row('Modo de energía', trailing: 'Balanceado'),
            _row('Escaneo Bluetooth', trailing: 'Normal'),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, {required IconData icon}) {
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

  Widget _row(String title,
      {required String trailing, Color? trailingColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1C))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          Text(trailing,
              style: TextStyle(
                color: trailingColor ?? AppTheme.textMuted,
                fontSize: 13,
                fontWeight: trailingColor != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              )),
          const Icon(Icons.chevron_right,
              color: AppTheme.textMuted, size: 20),
        ],
      ),
    );
  }
}
