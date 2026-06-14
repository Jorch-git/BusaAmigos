import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../models/member.dart';
import '../services/group_controller.dart';
import '../services/map/cached_tile_provider.dart';
import '../services/map/tile_cache_service.dart';
import 'compass_screen.dart';
import 'download_region_screen.dart';

/// Pestaña de mapa: muestra a los miembros del grupo sobre un mapa real de
/// OpenStreetMap. Usa el [CachedTileProvider] para que funcione offline si la
/// zona fue descargada previamente.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  bool _followSelf = true;

  /// Centro por defecto si todavía no hay GPS (Foro Sol, CDMX).
  static const _fallbackCenter = LatLng(19.4044, -99.0975);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Centra el mapa en la posición del usuario.
  void _centerOnSelf(GroupController controller) {
    final pos = controller.group?.self?.lastPosition;
    if (pos != null && pos.hasGps) {
      _mapController.move(LatLng(pos.latitude!, pos.longitude!),
          _mapController.camera.zoom);
      setState(() => _followSelf = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final selfPos = group.self?.lastPosition;
    final center = (selfPos != null && selfPos.hasGps)
        ? LatLng(selfPos.latitude!, selfPos.longitude!)
        : _fallbackCenter;

    // Si estamos en modo "seguir" y hay posición, recentramos suavemente.
    if (_followSelf && selfPos != null && selfPos.hasGps) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            _mapController.move(center, _mapController.camera.zoom);
          } catch (_) {}
        }
      });
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            minZoom: 3,
            maxZoom: 19,
            // Si el usuario arrastra el mapa, dejamos de seguirlo.
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture && _followSelf) {
                setState(() => _followSelf = false);
              }
            },
          ),
          children: [
            // Capa de tiles con caché offline.
            TileLayer(
              urlTemplate: TileCacheService.tileUrlTemplate,
              tileProvider: CachedTileProvider(),
              userAgentPackageName: 'com.buscamigos.app',
              maxNativeZoom: 19,
            ),

            // Círculo de precisión del usuario.
            if (selfPos != null && selfPos.hasGps && selfPos.accuracy != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(selfPos.latitude!, selfPos.longitude!),
                    radius: selfPos.accuracy!,
                    useRadiusInMeter: true,
                    color: const Color(0xFF378ADD).withValues(alpha: 0.15),
                    borderColor: const Color(0xFF378ADD).withValues(alpha: 0.4),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),

            // Marcadores: miembros + self.
            MarkerLayer(
              markers: _buildMarkers(group, selfPos),
            ),

            // Atribución obligatoria de OpenStreetMap.
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),

        // Header con nombre del grupo y estado.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildHeader(context, group),
        ),

        // Botones flotantes a la derecha.
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(
            children: [
              // Descargar zona offline.
              FloatingActionButton(
                heroTag: 'download',
                backgroundColor: AppTheme.cardBgOf(context),
                onPressed: () => _openDownload(context),
                tooltip: 'Descargar mapa offline',
                child: const Icon(Icons.download_for_offline,
                    color: AppTheme.accentGreen),
              ),
              const SizedBox(height: 12),
              // Centrar en mí.
              FloatingActionButton(
                heroTag: 'center',
                backgroundColor: _followSelf
                    ? AppTheme.accentGreen
                    : AppTheme.cardBgOf(context),
                onPressed: () => _centerOnSelf(controller),
                tooltip: 'Centrar en mi ubicación',
                child: Icon(
                  Icons.my_location,
                  color: _followSelf ? Colors.black : AppTheme.accentGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(group, selfPos) {
    final markers = <Marker>[];

    // Miembros (otros).
    for (final m in group.others) {
      final pos = m.lastPosition;
      if (pos == null || !pos.hasGps) continue;
      markers.add(
        Marker(
          point: LatLng(pos.latitude!, pos.longitude!),
          width: 80,
          height: 70,
          child: _MemberPin(member: m, onTap: () => _openCompass(m)),
        ),
      );
    }

    // Self (el usuario) — punto azul.
    if (selfPos != null && selfPos.hasGps) {
      markers.add(
        Marker(
          point: LatLng(selfPos.latitude!, selfPos.longitude!),
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF378ADD),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF378ADD).withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildHeader(BuildContext context, group) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.scaffoldBgOf(context).withValues(alpha: 0.95),
            AppTheme.scaffoldBgOf(context).withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.cardBgOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map, color: AppTheme.accentGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${group.connectedCount} en el mapa',
                    style: TextStyle(
                        color: AppTheme.textMutedOf(context), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openCompass(Member m) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompassScreen(targetMemberId: m.id)),
    );
  }

  void _openDownload(BuildContext context) {
    // Pasamos el centro actual del mapa para que la descarga use esa zona.
    final camera = _mapController.camera;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadRegionScreen(
          centerLat: camera.center.latitude,
          centerLng: camera.center.longitude,
          currentZoom: camera.zoom.round(),
        ),
      ),
    );
  }
}

/// Pin de un miembro en el mapa: avatar circular con su color + nombre.
class _MemberPin extends StatelessWidget {
  final Member member;
  final VoidCallback onTap;

  const _MemberPin({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(member.colorSeed);
    final isOnline = member.status == MemberStatus.online;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              member.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isOnline ? Colors.white : Colors.white54,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    member.displayName.isNotEmpty
                        ? member.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              if (!isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEC42E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
