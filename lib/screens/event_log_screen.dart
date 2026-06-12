import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/theme/app_theme.dart';
import '../services/group_controller.dart';
import '../services/logging/event_log_service.dart';
import '../services/logging/log_exporter.dart';

/// Última ventana del flujo: muestra TODO lo que se mandó y se recibió durante
/// la sesión (en claro, descomprimido) y permite exportarlo a JSON/CSV para
/// análisis posterior.
class EventLogScreen extends StatefulWidget {
  const EventLogScreen({super.key});

  @override
  State<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends State<EventLogScreen> {
  bool _exporting = false;
  LogDirection? _filter; // null = todos

  @override
  Widget build(BuildContext context) {
    final log = context.watch<EventLogService>();
    final controller = context.read<GroupController>();

    final entries = _filter == null
        ? log.entries.reversed.toList()
        : log.entries.where((e) => e.direction == _filter).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de la sesión'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Limpiar',
            onPressed: log.count == 0 ? null : () => log.clear(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _summary(log),
            _filterBar(log),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('Sin eventos todavía',
                          style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _tile(entries[i]),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _exportBar(log, controller),
    );
  }

  Widget _summary(EventLogService log) {
    final sent = log.countByDirection(LogDirection.sent);
    final recv = log.countByDirection(LogDirection.received);
    final ratioPct = (log.compressionRatio * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _chip('Eventos', '${log.count}'),
          _chip('Enviados', '$sent'),
          _chip('Recibidos', '$recv'),
          _chip('En el cable', _humanBytes(log.totalWireBytes)),
          _chip('Comprimido a', '$ratioPct%'),
        ],
      ),
    );
  }

  Widget _filterBar(EventLogService log) {
    Widget seg(String label, LogDirection? d) {
      final on = _filter == d;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          onSelected: (_) => setState(() => _filter = d),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        seg('Todos', null),
        seg('Enviados', LogDirection.sent),
        seg('Recibidos', LogDirection.received),
        seg('Sistema', LogDirection.system),
      ]),
    );
  }

  Widget _tile(LogEntry e) {
    final color = switch (e.direction) {
      LogDirection.sent => AppTheme.accentGreen,
      LogDirection.received => const Color(0xFF378ADD),
      LogDirection.system => AppTheme.textMuted,
    };
    final icon = switch (e.direction) {
      LogDirection.sent => Icons.north_east,
      LogDirection.received => Icons.south_west,
      LogDirection.system => Icons.info_outline,
    };
    final t = e.timestamp;
    String two(int x) => x.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

    return ExpansionTile(
      leading: Icon(icon, color: color, size: 20),
      title: Row(
        children: [
          Text(e.type, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (e.memberName != null)
            Expanded(
              child: Text(e.memberName!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
        ],
      ),
      subtitle: Text(
        '$time · ${e.wireBytes > 0 ? '${e.wireBytes} B${e.compressed ? ' (gz)' : ''}' : '—'}',
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            _pretty(e.payload),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _exportBar(EventLogService log, GroupController controller) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: _exporting
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: const Text('Exportar y compartir'),
                onPressed: (_exporting || log.count == 0)
                    ? null
                    : () => _export(log, controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(EventLogService log, GroupController controller) async {
    setState(() => _exporting = true);
    try {
      final meta = {
        'group': controller.group?.name,
        'code': controller.group?.code,
        'members': controller.group?.members.map((m) => m.displayName).toList(),
      };
      final jsonFile = await LogExporter.exportJson(log, sessionMeta: meta);
      final csvFile = await LogExporter.exportCsv(log);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(jsonFile.path), XFile(csvFile.path)],
          subject: 'Buscamigos · registro de sesión',
          text: 'Log de ${log.count} eventos (JSON + CSV).',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---- Helpers ----

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.radarGrid.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }

  String _pretty(Map<String, dynamic> m) {
    final sb = StringBuffer();
    m.forEach((k, v) => sb.writeln('$k: $v'));
    return sb.toString().trimRight();
  }

  String _humanBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
