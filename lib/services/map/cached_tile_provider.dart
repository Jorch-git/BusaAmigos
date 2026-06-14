import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'tile_cache_service.dart';

/// TileProvider para flutter_map que implementa caché offline-first:
///
///  1. Cuando flutter_map pide un tile (z,x,y), primero lo buscamos en disco
///     vía [TileCacheService]. Si está, lo servimos desde ahí (funciona sin
///     internet).
///  2. Si no está en disco y hay red, lo bajamos, lo mostramos y lo
///     guardamos para la próxima.
///  3. Si no está en disco y no hay red, flutter_map mostrará el tile como
///     "faltante" (gris). Por eso la descarga previa de la zona es clave.
///
/// Esto reemplaza al NetworkTileProvider estándar de flutter_map.
class CachedTileProvider extends TileProvider {
  CachedTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
  }
}

/// ImageProvider que resuelve un tile desde disco o red.
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final int z;
  final int x;
  final int y;

  const _CachedTileImage({required this.z, required this.x, required this.y});

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadBytes(decode),
      scale: 1.0,
      debugLabel: 'tile $z/$x/$y',
    );
  }

  Future<ui.Codec> _loadBytes(ImageDecoderCallback decode) async {
    final cache = TileCacheService.instance;

    // 1. Intentar desde disco.
    final cached = await cache.readTile(z, x, y);
    if (cached != null && cached.isNotEmpty) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(cached);
      return decode(buffer);
    }

    // 2. No está en disco: intentar red.
    try {
      final url = TileCacheService.tileUrlTemplate
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': TileCacheService.userAgent},
      );
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        // Guardar para la próxima (offline).
        await cache.writeTile(z, x, y, resp.bodyBytes);
        final buffer = await ui.ImmutableBuffer.fromUint8List(resp.bodyBytes);
        return decode(buffer);
      }
    } catch (e) {
      debugPrint('CachedTileProvider: sin red para tile $z/$x/$y: $e');
    }

    // 3. Ni disco ni red: tile transparente 1×1 para no romper el render.
    final transparent = await ui.ImmutableBuffer.fromUint8List(_transparentPng);
    return decode(transparent);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

/// PNG transparente de 1×1 px (para tiles no disponibles offline).
final Uint8List _transparentPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
