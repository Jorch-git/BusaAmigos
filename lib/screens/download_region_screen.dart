import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme/app_theme.dart';
import '../services/map/tile_cache_service.dart';

/// Pantalla para descargar una zona del mapa para uso offline.
///
/// El usuario elige:
///  - El RADIO alrededor del centro actual (cuánta área).
///  - El NIVEL DE DETALLE (zoom máximo): más detalle = muchos más tiles.
///
/// Le mostramos en tiempo real cuántos tiles implica y el tamaño estimado,
/// para que decida con información antes de descargar.
class DownloadRegionScreen extends StatefulWidget {
  final double centerLat;
  final double centerLng;
  final int currentZoom;

  const DownloadRegionScreen({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.currentZoom,
  });

  @override
  State<DownloadRegionScreen> createState() => _DownloadRegionScreenState();
}

class _DownloadRegionScreenState extends State<DownloadRegionScreen> {
  // Radio en km alrededor del centro.
  double _radiusKm = 1.0;

  // Zoom máximo a descargar. minZoom siempre será 13 (vista de barrio).
  int _maxZoom = 17;
  static const int _minZoom = 13;

  bool _downloading = false;
  int _done = 0;
  int _total = 0;
  TileDownloadCancelToken? _cancelToken;

  /// Calcula el bounding box (norte/sur/este/oeste) a partir del centro y radio.
  ({double north, double south, double east, double west}) _bbox() {
    // 1 grado de latitud ≈ 111 km. Longitud varía con el coseno de la latitud.
    final dLat = _radiusKm / 111.0;
    final dLng = _radiusKm / (111.0 * math.cos(widget.centerLat * math.pi / 180));
    return (
      north: widget.centerLat + dLat,
      south: widget.centerLat - dLat,
      east: widget.centerLng + dLng,
      west: widget.centerLng - dLng,
    );
  }

  int get _tileCount {
    final b = _bbox();
    return TileCacheService.countTiles(
      north: b.north, south: b.south, east: b.east, west: b.west,
      minZoom: _minZoom, maxZoom: _maxZoom,
    );
  }

  Future<void> _startDownload() async {
    final b = _bbox();
    _cancelToken = TileDownloadCancelToken();
    setState(() {
      _downloading = true;
      _done = 0;
      _total = _tileCount;
    });

    final ok = await TileCacheService.instance.downloadRegion(
      north: b.north, south: b.south, east: b.east, west: b.west,
      minZoom: _minZoom, maxZoom: _maxZoom,
      cancelToken: _cancelToken,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() => _downloading = false);

    final cancelled = _cancelToken?.isCancelled ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cancelled
            ? 'Descarga cancelada. Se guardaron $ok tiles.'
            : '✅ Zona descargada: $ok tiles listos para usar sin conexión.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final tileCount = _tileCount;
    final sizeEstimate = TileCacheService.estimateSize(tileCount);
    // Advertencia si la descarga es muy grande (política de OSM + tiempo).
    final isLarge = tileCount > 5000;

    return Scaffold(
      appBar: AppBar(title: const Text('Descargar mapa offline')),
      body: SafeArea(
        child: _downloading
            ? _buildProgress()
            : _buildConfig(tileCount, sizeEstimate, isLarge),
      ),
    );
  }

  Widget _buildConfig(int tileCount, String sizeEstimate, bool isLarge) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoCard(
            icon: Icons.info_outline,
            text: 'Se descargará el área alrededor del centro actual del mapa. '
                'Úsalo antes de entrar al evento, con buena conexión WiFi.',
          ),
          const SizedBox(height: 24),

          // Radio.
          _label('Radio de cobertura'),
          const SizedBox(height: 4),
          Text(
            '${_radiusKm.toStringAsFixed(1)} km a la redonda',
            style: const TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          Slider(
            value: _radiusKm,
            min: 0.5,
            max: 5.0,
            divisions: 9,
            activeColor: AppTheme.accentGreen,
            label: '${_radiusKm.toStringAsFixed(1)} km',
            onChanged: (v) => setState(() => _radiusKm = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.5 km',
                  style: TextStyle(
                      color: AppTheme.textMutedOf(context), fontSize: 11)),
              Text('5 km',
                  style: TextStyle(
                      color: AppTheme.textMutedOf(context), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 24),

          // Nivel de detalle (zoom máximo).
          _label('Nivel de detalle'),
          const SizedBox(height: 4),
          Text(
            _zoomLabel(_maxZoom),
            style: const TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          Slider(
            value: _maxZoom.toDouble(),
            min: 15,
            max: 19,
            divisions: 4,
            activeColor: AppTheme.accentGreen,
            label: 'Zoom $_maxZoom',
            onChanged: (v) => setState(() => _maxZoom = v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Calles principales',
                  style: TextStyle(
                      color: AppTheme.textMutedOf(context), fontSize: 11)),
              Text('Máximo detalle',
                  style: TextStyle(
                      color: AppTheme.textMutedOf(context), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 24),

          // Resumen de la descarga.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBgOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _summaryRow('Tiles a descargar', '$tileCount'),
                const SizedBox(height: 8),
                _summaryRow('Espacio estimado', sizeEstimate),
                const SizedBox(height: 8),
                _summaryRow('Tiempo aprox.',
                    '~${(tileCount * 0.05 / 60).ceil()} min'),
              ],
            ),
          ),

          if (isLarge) ...[
            const SizedBox(height: 16),
            _infoCard(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFEF9F27),
              text: 'Esta descarga es grande ($tileCount tiles). Tardará y usará '
                  'datos. Considera reducir el radio o el detalle. La descarga '
                  'masiva del servidor público de OSM no está permitida para uso '
                  'intensivo.',
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Descargar esta zona'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: _startDownload,
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final pct = _total > 0 ? (_done / _total) : 0.0;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 8,
                    color: AppTheme.accentGreen,
                    backgroundColor: AppTheme.cardBgOf(context),
                  ),
                ),
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Descargando mapa…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '$_done de $_total tiles',
            style: TextStyle(color: AppTheme.textMutedOf(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'Mantén la app abierta',
            style: TextStyle(
                color: AppTheme.textMutedOf(context), fontSize: 12),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: _cancelDownload,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(200, 48),
              foregroundColor: AppTheme.sosRed,
              side: const BorderSide(color: AppTheme.sosRed),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(text,
        style: TextStyle(
            color: AppTheme.textMutedOf(context),
            fontSize: 13,
            fontWeight: FontWeight.w600));
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedOf(context))),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final c = color ?? AppTheme.accentGreen;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: AppTheme.textMutedOf(context),
                    fontSize: 12,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  String _zoomLabel(int zoom) {
    switch (zoom) {
      case 15:
        return 'Calles principales';
      case 16:
        return 'Calles y plazas';
      case 17:
        return 'Edificios (recomendado)';
      case 18:
        return 'Detalle alto';
      case 19:
        return 'Máximo detalle';
      default:
        return 'Zoom $zoom';
    }
  }
}
