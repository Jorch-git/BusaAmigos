import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/theme/app_theme.dart';
import '../models/member.dart';
import '../services/group_controller.dart';

/// Permite volver a mostrar el QR/código del grupo después de creado, para
/// que se sumen más miembros. Además lista quién ya está confirmado vs
/// quién aún no responde, basado en el estado de proximidad y heartbeat.
class ShareQrScreen extends StatelessWidget {
  const ShareQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final code = group.code;
    final others = group.others;
    final confirmed = others.where((m) => m.status == MemberStatus.online).toList();
    final stale = others.where((m) => m.status == MemberStatus.stale).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitar a más amigos'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Comparte este código',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Tus amigos lo pueden escanear o teclear para entrar al grupo.',
                style: TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: code,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text('Código del grupo',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    SelectableText(
                      code,
                      style: const TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código copiado')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Sección de estado: quién ya está dentro y quién falta.
              const Text('Estado de los miembros',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),

              if (others.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.hourglass_empty, color: AppTheme.textMuted),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Aún no se ha unido nadie. Comparte el código para que entren.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if (confirmed.isNotEmpty) ...[
                  _sectionHeader(
                    icon: Icons.check_circle,
                    color: AppTheme.accentGreen,
                    text: '${confirmed.length} confirmado${confirmed.length == 1 ? '' : 's'} cerca',
                  ),
                  for (final m in confirmed) _buildMemberRow(m, isConfirmed: true),
                ],
                if (stale.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionHeader(
                    icon: Icons.access_time,
                    color: AppTheme.textMuted,
                    text: '${stale.length} sin señal reciente',
                  ),
                  for (final m in stale) _buildMemberRow(m, isConfirmed: false),
                ],
              ],

              const SizedBox(height: 24),

              // Recordatorio honesto sobre la verificación física.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppTheme.accentGreen),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aparece como "confirmado" cuando el celular del amigo está físicamente cerca y responde al heartbeat.',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ],
      ),
    );
  }

  Widget _buildMemberRow(Member m, {required bool isConfirmed}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
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
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(m.displayName,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          if (isConfirmed)
            const Icon(Icons.check_circle,
                color: AppTheme.accentGreen, size: 18)
          else
            Text(
              m.lastPosition != null
                  ? 'hace ${m.lastPosition!.age.inSeconds}s'
                  : 'sin señal',
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
