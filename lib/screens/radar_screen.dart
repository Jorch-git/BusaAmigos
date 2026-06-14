import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/theme/app_theme.dart';
import '../models/member.dart';
import '../services/group_controller.dart';
import '../services/transport/transport_service.dart';
import '../widgets/radar_widget.dart';
import '../widgets/sos_button.dart';
import 'chat_screen.dart';
import 'compass_screen.dart';
import 'console_screen.dart';
import 'group_screen.dart';
import 'map_screen.dart';
import 'sos_screen.dart';

/// La pantalla central. Cuatro pestañas: Radar, Chat, Grupo, Consola.
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  int _tabIndex = 0;
  double _radius = 50;
  bool _searchMode = false;

  StreamSubscription? _sosSub;
  bool _sosScreenOpen = false;
  GroupController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = Provider.of<GroupController>(context, listen: false);
    _sosSub = _controller!.sosIncomingStream.listen(_onIncomingSos);
  }

  void _onIncomingSos(alert) {
    if (!mounted) return;
    if (alert.triggeredBy == _controller?.group?.self?.id) return;
    if (_sosScreenOpen) return;
    _sosScreenOpen = true;
    Future.microtask(() {
      if (!mounted) {
        _sosScreenOpen = false;
        return;
      }
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SosScreen()))
          .then((_) => _sosScreenOpen = false);
    });
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    if (_searchMode) {
      WakelockPlus.disable();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = [
      _buildRadarTab(controller),
      const MapScreen(),
      const ChatScreen(),
      const GroupScreen(),
      const ConsoleScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tabIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        backgroundColor: AppTheme.cardBgOf(context),
        selectedItemColor: AppTheme.accentGreen,
        unselectedItemColor: AppTheme.textMutedOf(context),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.radar), label: 'Radar'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined), label: 'Mapa'),
          BottomNavigationBarItem(
            icon: _ChatIconWithBadge(unread: controller.unreadCount),
            label: 'Chat',
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.group_outlined), label: 'Grupo'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.developer_board), label: 'Consola'),
        ],
      ),
    );
  }

  Widget _buildRadarTab(GroupController controller) {
    final group = controller.group!;
    return Column(
      children: [
        _buildHeader(group.name, controller),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: RadarWidget(
                  group: group,
                  selfHeading: controller.selfHeading,
                  radiusMeters: _radius,
                  onMemberTap: (m) => _openCompass(m),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _buildScaleSelector(),
              ),
              Positioned(
                bottom: 24,
                left: 16,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(_searchMode ? 'Búsqueda ON' : 'Modo búsqueda'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _searchMode ? const Color(0xFFEF9F27) : AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onPressed: _toggleSearchMode,
                ),
              ),
              Positioned(
                bottom: 24,
                right: 16,
                child: SosButton(
                  onPressed: () => _openSos(controller),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String groupName, GroupController controller) {
    final connected = controller.group!.connectedCount;
    final transportState = controller.transportState;
    final reach = controller.transport.reach;
    final pending = controller.pendingMessagesCount;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (transportState) {
      case TransportState.idle:
        statusText = 'Desconectado';
        statusColor = AppTheme.sosRed;
        statusIcon = Icons.wifi_off;
        break;
      case TransportState.connecting:
        statusText = 'Conectando...';
        statusColor = AppTheme.textMuted;
        statusIcon = Icons.wifi_find;
        break;
      case TransportState.connected:
        if (reach == TransportReach.local) {
          statusText = '$connected cerca (P2P)';
          statusColor = AppTheme.accentGreen;
          statusIcon = Icons.bluetooth_connected;
        } else {
          statusText = '$connected conectados';
          statusColor = AppTheme.accentGreen;
          statusIcon = Icons.wifi;
        }
        break;
      case TransportState.degraded:
        statusText = 'Sin conexiones cercanas';
        statusColor = AppTheme.textMuted;
        statusIcon = Icons.bluetooth_searching;
        break;
      case TransportState.error:
        statusText = 'Error de conexión';
        statusColor = AppTheme.sosRed;
        statusIcon = Icons.error_outline;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(groupName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    if (const bool.fromEnvironment('dart.vm.product') == false)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () => _resendHello(controller),
                        tooltip: 'Reenviar saludo',
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusText,
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12)),
                    if (pending > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 10, color: AppTheme.textMuted),
                            const SizedBox(width: 3),
                            Text('$pending pendientes',
                                style: const TextStyle(
                                    color: AppTheme.textMuted, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (_searchMode)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF9F27).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.battery_charging_full,
                            size: 12, color: Color(0xFFEF9F27)),
                        SizedBox(width: 6),
                        Text('Modo búsqueda activo - pantalla encendida',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 10)),
                      ],
                    ),
                  ),
                if (reach == TransportReach.local && controller.group?.self?.lastPosition == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'PIN cercano por BT: ${controller.group?.code ?? ''}',
                      style: const TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (transportState == TransportState.degraded ||
                    transportState == TransportState.connecting)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Asegúrate de que los dispositivos estén cerca (≤30m) y con Bluetooth activado',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _resendHello(GroupController controller) {
    controller.resendHello();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reenviando mensaje de saludo...')),
    );
  }

  Future<void> _toggleSearchMode() async {
    final enable = !_searchMode;
    if (enable) {
      WakelockPlus.enable();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      setState(() => _searchMode = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Modo búsqueda activo: pantalla encendida, la batería consumirá más rápido'),
      ));
    } else {
      WakelockPlus.disable();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (!mounted) return;
      setState(() => _searchMode = false);
    }
  }

  Widget _buildScaleSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [10.0, 50.0, 100.0].map((r) {
          final selected = _radius == r;
          return GestureDetector(
            onTap: () => setState(() => _radius = r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppTheme.accentGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${r.toInt()}m',
                style: TextStyle(
                  color: selected ? Colors.black : AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openCompass(Member m) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompassScreen(targetMemberId: m.id)),
    );
  }

  void _openSos(GroupController controller) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('¿Activar SOS?'),
        content: const Text(
          'Tus amigos recibirán una alerta de emergencia con tu ubicación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.sosRed,
                foregroundColor: Colors.white),
            onPressed: () async {
              await controller.triggerSos();
              if (!mounted) return;
              Navigator.pop(context);
              _sosScreenOpen = true;
              Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SosScreen()))
                  .then((_) => _sosScreenOpen = false);
            },
            child: const Text('Activar SOS'),
          ),
        ],
      ),
    );
  }
}

/// Icono de la pestaña Chat con un badge rojo que muestra el número de
/// mensajes no leídos. Si no hay no leídos, muestra el icono normal.
class _ChatIconWithBadge extends StatelessWidget {
  final int unread;
  const _ChatIconWithBadge({required this.unread});

  @override
  Widget build(BuildContext context) {
    if (unread <= 0) {
      return const Icon(Icons.chat_bubble_outline);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble),
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            decoration: BoxDecoration(
              color: AppTheme.sosRed,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppTheme.cardBgOf(context), width: 1.5),
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
