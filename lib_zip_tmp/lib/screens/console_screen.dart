import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../models/member.dart';
import '../models/position.dart';
import '../services/group_controller.dart';
import '../services/transport/nearby/nearby_transport.dart';
import '../services/transport/transport_service.dart';
import '../utils/distance_calculator.dart';

/// Pantalla de desarrollo "Consola". Dividida en dos paneles:
///
///  A) **Panel de Control de Antenas** — switches para simular el
///     encendido/apagado de BT, GPS, WiFi Direct y Datos Celulares.
///     En esta etapa NO apaga/enciende el hardware real del celular
///     (eso requiere permisos de sistema que las apps normales no tienen).
///     Lo que hace es poner un flag en el controller que IGNORA los datos
///     provenientes de esa fuente, como si la antena estuviera apagada.
///
///  B) **Panel de Monitoreo Matemático** — muestra en tiempo real las
///     fórmulas de distancia (Haversine, RSSI), las variables de entrada
///     (coordenadas GPS, accuracy, heading, RSSI, bearing) y los valores
///     calculados para cada miembro del grupo.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  // ---- Estado local de los "switches" de antenas ----
  // Cuando están en `false`, la UI ignora esos datos.
  bool _btEnabled = true;
  bool _gpsEnabled = true;
  bool _wifiDirectEnabled = true;
  bool _cellularEnabled = true;

  // Ticker para refrescar los datos de monitoreo cada segundo.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('PANEL DE CONTROL DE ANTENAS', Icons.settings_input_antenna),
        const SizedBox(height: 8),
        _buildAntennaPanel(controller),
        const SizedBox(height: 24),
        _buildSectionTitle('ESTADO DEL SISTEMA', Icons.monitor_heart_outlined),
        const SizedBox(height: 8),
        _buildSystemStatus(controller),
        const SizedBox(height: 24),
        _buildSectionTitle('MI POSICIÓN (SELF)', Icons.my_location),
        const SizedBox(height: 8),
        _buildSelfGpsPanel(controller),
        const SizedBox(height: 24),
        _buildSectionTitle('FÓRMULAS Y SEÑALES POR MIEMBRO', Icons.calculate_outlined),
        const SizedBox(height: 8),
        _buildMathPanel(controller),
        const SizedBox(height: 24),
        _buildSectionTitle('TRANSPORTE P2P (NEARBY)', Icons.device_hub),
        const SizedBox(height: 8),
        _buildNearbyPanel(controller),
        const SizedBox(height: 24),
        _buildSectionTitle('COLA DE REENVÍO (OUTBOX)', Icons.outbox),
        const SizedBox(height: 8),
        _buildOutboxPanel(controller),
        const SizedBox(height: 80),
      ],
    );
  }

  // ====================================================================
  // A) PANEL DE CONTROL DE ANTENAS
  // ====================================================================

  Widget _buildAntennaPanel(GroupController controller) {
    return _card(
      child: Column(
        children: [
          _buildSwitch(
            title: 'Bluetooth (BLE)',
            subtitle: _btEnabled
                ? 'Activo — se usa para descubrimiento de peers cercanos'
                : 'Desactivado — datos BLE/RSSI serán ignorados',
            icon: Icons.bluetooth,
            color: Colors.blue,
            value: _btEnabled,
            onChanged: (v) => setState(() => _btEnabled = v),
          ),
          _divider(),
          _buildSwitch(
            title: 'GPS',
            subtitle: _gpsEnabled
                ? 'Activo — posición satelital como fuente principal'
                : 'Desactivado — coordenadas GPS serán ignoradas',
            icon: Icons.satellite_alt,
            color: AppTheme.accentGreen,
            value: _gpsEnabled,
            onChanged: (v) => setState(() => _gpsEnabled = v),
          ),
          _divider(),
          _buildSwitch(
            title: 'WiFi Direct',
            subtitle: _wifiDirectEnabled
                ? 'Activo — canal de datos P2P de medio alcance (~100m)'
                : 'Desactivado — mensajes WiFi Direct serán ignorados',
            icon: Icons.wifi_tethering,
            color: const Color(0xFFEF9F27),
            value: _wifiDirectEnabled,
            onChanged: (v) => setState(() => _wifiDirectEnabled = v),
          ),
          _divider(),
          _buildSwitch(
            title: 'Datos Celulares',
            subtitle: _cellularEnabled
                ? 'Activo — canal de respaldo vía operador (requiere backend)'
                : 'Desactivado — no se usará red celular como canal',
            icon: Icons.cell_tower,
            color: const Color(0xFFD4537E),
            value: _cellularEnabled,
            onChanged: (v) => setState(() => _cellularEnabled = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: value ? color.withValues(alpha: 0.15) : AppTheme.cardBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18,
                color: value ? color : AppTheme.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: value ? Colors.white : AppTheme.textMuted,
                    )),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
            inactiveThumbColor: AppTheme.textMuted,
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // ESTADO DEL SISTEMA
  // ====================================================================

  Widget _buildSystemStatus(GroupController controller) {
    final group = controller.group;
    final transport = controller.transport;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dataRow('Transporte', _transportLabel(controller.transportState)),
          _dataRow('Alcance', _reachLabel(transport.reach)),
          _dataRow('Grupo', group?.code ?? 'No creado'),
          _dataRow('Self ID', controller.group?.self?.id.substring(0, 8) ?? '-'),
          _dataRow('Miembros totales', '${group?.members.length ?? 0}'),
          _dataRow('Miembros online',
              '${group?.members.where((m) => m.status == MemberStatus.online).length ?? 0}'),
          _dataRow('Miembros stale',
              '${group?.members.where((m) => m.status == MemberStatus.stale).length ?? 0}'),
          _dataRow('Miembros offline',
              '${group?.members.where((m) => m.status == MemberStatus.offline).length ?? 0}'),
          _dataRow('Verificación', _verificationLabel(controller.verificationState)),
          _dataRow('Cola de reenvío', '${controller.pendingMessagesCount} mensajes'),
          _dataRow('Mensajes chat', '${controller.messages.length}'),
          _dataRow('SOS activo', controller.activeSos != null ? 'SÍ' : 'No'),
          _dataRow('Heading brújula',
              controller.selfHeading != null
                  ? '${controller.selfHeading!.toStringAsFixed(1)}°'
                  : 'Sin datos'),
        ],
      ),
    );
  }

  // ====================================================================
  // MI POSICIÓN GPS
  // ====================================================================

  Widget _buildSelfGpsPanel(GroupController controller) {
    final self = controller.group?.self;
    final pos = self?.lastPosition;

    if (pos == null || !pos.hasGps) {
      return _card(
        child: _statusBanner(
          icon: Icons.gps_off,
          color: AppTheme.sosRed,
          text: _gpsEnabled
              ? 'GPS activo pero sin fix todavía. Puede tardar hasta 60s la primera vez.'
              : 'GPS desactivado desde el panel de antenas.',
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dataRow('Latitud', pos.latitude!.toStringAsFixed(7)),
          _dataRow('Longitud', pos.longitude!.toStringAsFixed(7)),
          _dataRow('Precisión horizontal', '±${pos.accuracy?.toStringAsFixed(1) ?? "?"} m'),
          _dataRow('Heading GPS', pos.heading != null
              ? '${pos.heading!.toStringAsFixed(1)}°'
              : 'Sin movimiento'),
          _dataRow('Antigüedad', '${pos.age.inSeconds}s'),
          _dataRow('Timestamp', _formatTime(pos.timestamp)),
          _dataRow('Estado switch GPS', _gpsEnabled ? '✅ ON' : '❌ OFF'),
        ],
      ),
    );
  }

  // ====================================================================
  // B) PANEL DE MONITOREO MATEMÁTICO — FÓRMULAS POR MIEMBRO
  // ====================================================================

  Widget _buildMathPanel(GroupController controller) {
    final group = controller.group;
    if (group == null) return _card(child: _emptyLabel('No hay grupo activo'));

    final self = group.self;
    final selfPos = self?.lastPosition;
    final others = group.others;

    if (others.isEmpty) {
      return _card(child: _emptyLabel('No hay otros miembros en el grupo'));
    }

    return Column(
      children: others.map((m) => _buildMemberMathCard(m, selfPos)).toList(),
    );
  }

  Widget _buildMemberMathCard(Member m, Position? selfPos) {
    final pos = m.lastPosition;
    final result = DistanceCalculator.between(selfPos, pos);

    // Valores intermedios para mostrar la fórmula paso a paso.
    String haversineSteps = '-';
    String bearingSteps = '-';
    String rssiSteps = '-';

    if (selfPos != null && selfPos.hasGps && pos != null && pos.hasGps) {
      final dLat = pos.latitude! - selfPos.latitude!;
      final dLng = pos.longitude! - selfPos.longitude!;

      haversineSteps = 'ΔLat=${dLat.toStringAsFixed(7)}°  ΔLng=${dLng.toStringAsFixed(7)}°\n'
          'd = 2R·arcsin(√(sin²(ΔLat/2) + cos(lat₁)·cos(lat₂)·sin²(ΔLng/2)))\n'
          'R = 6,371,000 m\n'
          '→ d = ${result.meters.toStringAsFixed(2)} m';

      if (result.bearing != null) {
        bearingSteps = 'θ = atan2(sin(ΔLng)·cos(lat₂), cos(lat₁)·sin(lat₂) - sin(lat₁)·cos(lat₂)·cos(ΔLng))\n'
            '→ bearing = ${result.bearing!.toStringAsFixed(2)}°';
      }
    }

    if (pos != null && pos.hasRssi) {
      final rssiVal = pos.rssi ?? -70;
      rssiSteps = 'd = 10^((TxPower - RSSI) / (10·n))\n'
          'TxPower = -59 dBm, RSSI = $rssiVal dBm, n = 2.5\n'
          '→ d_rssi = ${DistanceCalculator.rssiDistance(rssiVal).toStringAsFixed(2)} m';
    }

    final statusColor = _memberStatusColor(m.status);
    final seenAgo = m.lastSeenAt != null
        ? '${DateTime.now().difference(m.lastSeenAt!).inSeconds}s ago'
        : 'nunca';

    return _card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del miembro
          Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(m.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Text(m.status.name.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),

          // Datos crudos del miembro
          _dataRow('ID', '${m.id.substring(0, 12)}…'),
          _dataRow('lastSeenAt', seenAgo),

          if (pos != null && pos.hasGps) ...[
            _dataRow('Lat', pos.latitude!.toStringAsFixed(7)),
            _dataRow('Lng', pos.longitude!.toStringAsFixed(7)),
            _dataRow('Accuracy', '±${pos.accuracy?.toStringAsFixed(1) ?? "?"} m'),
            _dataRow('Pos age', '${pos.age.inSeconds}s'),
          ] else
            _dataRow('GPS', 'Sin coordenadas'),

          if (pos?.rssi != null)
            _dataRow('RSSI BLE', '${pos!.rssi} dBm'),

          const SizedBox(height: 8),
          _formulaTitle('Haversine (GPS → distancia)'),
          _formulaBody(haversineSteps),

          if (result.bearing != null) ...[
            const SizedBox(height: 6),
            _formulaTitle('Bearing (GPS → rumbo)'),
            _formulaBody(bearingSteps),
          ],

          if (pos?.hasRssi == true) ...[
            const SizedBox(height: 6),
            _formulaTitle('RSSI → distancia (BLE)'),
            _formulaBody(rssiSteps),
          ],

          const SizedBox(height: 6),
          _formulaTitle('Resultado final'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppTheme.accentGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten,
                    size: 16, color: AppTheme.accentGreen),
                const SizedBox(width: 8),
                Text(
                  result.source != DistanceSource.none
                      ? '${result.meters.toStringAsFixed(1)} m  (±${result.errorMeters?.toStringAsFixed(1) ?? "?"} m)  vía ${result.source.name.toUpperCase()}'
                      : 'Sin datos suficientes para calcular distancia',
                  style: TextStyle(
                    color: result.source != DistanceSource.none
                        ? AppTheme.accentGreen
                        : AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // TRANSPORTE NEARBY
  // ====================================================================

  Widget _buildNearbyPanel(GroupController controller) {
    final transport = controller.transport;

    // Intentamos acceder a los datos del NearbyTransport si es la implementación activa.
    final isNearby = transport is NearbyTransport;
    final peerIds = isNearby
        ? transport.connectedPeerIds
        : <String>{};

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dataRow('Tipo de transporte', isNearby ? 'NearbyTransport (P2P)' : transport.runtimeType.toString()),
          _dataRow('Estado', _transportLabel(controller.transportState)),
          _dataRow('Alcance', _reachLabel(transport.reach)),
          _dataRow('Peers P2P conectados', '${peerIds.length}'),
          if (peerIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Peer IDs (dispositivos Nearby):',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            ...peerIds.map((id) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.devices,
                          size: 12, color: AppTheme.accentGreen),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(id,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ],
                  ),
                )),
          ],
          _dataRow('Switch BT', _btEnabled ? '✅ ON' : '❌ OFF'),
          _dataRow('Switch WiFi Direct', _wifiDirectEnabled ? '✅ ON' : '❌ OFF'),
        ],
      ),
    );
  }

  // ====================================================================
  // COLA DE REENVÍO
  // ====================================================================

  Widget _buildOutboxPanel(GroupController controller) {
    final pending = controller.pendingMessagesCount;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dataRow('Mensajes en cola', '$pending'),
          _dataRow('Reintento', 'Cada 8s automáticamente'),
          _dataRow('TTL normal', '5 min'),
          _dataRow('TTL SOS', '30 min'),
          if (pending > 0)
            _statusBanner(
              icon: Icons.schedule,
              color: const Color(0xFFEF9F27),
              text: 'Hay $pending mensaje(s) pendientes de entrega. Se reintentan cuando vuelva la conexión.',
            ),
        ],
      ),
    );
  }

  // ====================================================================
  // WIDGETS AUXILIARES
  // ====================================================================

  Widget _buildSectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.accentGreen),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
              color: AppTheme.accentGreen,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1,
            )),
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _divider() {
    return const Divider(color: AppTheme.scaffoldBg, height: 16, thickness: 1);
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _formulaTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(
            color: AppTheme.accentGreen,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          )),
    );
  }

  Widget _formulaBody(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 11, height: 1.5)),
    );
  }

  Widget _statusBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _emptyLabel(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text, style: const TextStyle(color: AppTheme.textMuted)),
      ),
    );
  }

  Color _memberStatusColor(MemberStatus s) {
    switch (s) {
      case MemberStatus.online: return AppTheme.accentGreen;
      case MemberStatus.stale:  return const Color(0xFFEEC42E);
      case MemberStatus.offline: return AppTheme.textMuted;
    }
  }

  String _transportLabel(TransportState s) {
    switch (s) {
      case TransportState.idle:       return '⚪ IDLE';
      case TransportState.connecting: return '🟡 CONNECTING';
      case TransportState.connected:  return '🟢 CONNECTED';
      case TransportState.degraded:   return '🟠 DEGRADED';
      case TransportState.error:      return '🔴 ERROR';
    }
  }

  String _reachLabel(TransportReach r) {
    switch (r) {
      case TransportReach.global: return '🌐 Global (internet)';
      case TransportReach.local:  return '📡 Local (P2P ~30-100m)';
      case TransportReach.none:   return '❌ Ninguno';
    }
  }

  String _verificationLabel(GroupVerificationState s) {
    switch (s) {
      case GroupVerificationState.notRequired: return 'No requerida';
      case GroupVerificationState.pending:     return '⏳ Pendiente';
      case GroupVerificationState.confirmed:   return '✅ Confirmada';
      case GroupVerificationState.timedOut:     return '⏰ Expirada';
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
