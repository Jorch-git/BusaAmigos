import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Servicio que cachea tiles (mosaicos) del mapa OpenStreetMap en disco para
/// uso sin conexión.
///
/// Cómo funciona un mapa de tiles:
///  - El mundo se divide en una cuadrícula de imágenes de 256×256 px.
///  - Cada tile se identifica por (z, x, y): z = nivel de zoom (0=todo el
///    mundo, 19=máximo detalle), x/y = posición en la cuadrícula a ese zoom.
///  - A zoom z hay 2^z × 2^z tiles. Por eso descargar mucho zoom = MUCHOS
///    tiles (zoom 17 de una ciudad entera son decenas de miles).
///
/// Estrategia de almacenamiento:
///  - Guardamos cada tile como un archivo PNG en
///    `<documents>/map_tiles/<z>/<x>/<y>.png`.
///  - El [CachedTileProvider] lee de ahí primero; si no existe y hay red,
///    lo baja y lo guarda para la próxima.
///
/// IMPORTANTE sobre la política de uso de OSM: el servidor público de tiles
/// de OpenStreetMap (tile.openstreetmap.org) tiene una política de uso justo
/// que PROHÍBE descargas masivas/bulk. Para un radio pequeño de uso personal
/// está bien, pero para producción real deberías usar un proveedor de tiles
/// propio o pagado (Mapbox, Stadia, Thunderforest, etc.). Por eso limitamos
/// la descarga y ponemos un User-Agent identificable, y un delay entre tiles.
class TileCacheService {
  TileCacheService._();
  static final TileCacheService instance = TileCacheService._();

  /// User-Agent requerido por la política de OSM. Cámbialo por el de tu app.
  static const String userAgent = 'BuscamigosApp/0.1 (contacto@ejemplo.com)';

  /// URL base del servidor de tiles. OSM estándar.
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  Directory? _cacheDir;

  /// Inicializa el directorio de caché. Es idempotente: llamarlo varias veces
  /// no hace daño. Se puede llamar al arrancar la app, pero ya NO es
  /// obligatorio: los métodos que usan el disco se auto-inicializan (ver
  /// _ensureInit), así que el mapa funciona aunque no se haya llamado init().
  Future<void> init() async {
    if (_cacheDir != null) return; // ya inicializado
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/map_tiles');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
  }

  /// Garantiza que el directorio esté listo antes de cualquier operación de
  /// disco. Esto hace al servicio a prueba de "olvidé llamar init()": si no se
  /// inicializó, lo hace ahora. Antes, usar el mapa sin init() lanzaba
  /// StateError y rompía la descarga.
  Future<Directory> _ensureInit() async {
    if (_cacheDir == null) {
      await init();
    }
    return _cacheDir!;
  }

  /// Ruta en disco para un tile (z, x, y). Si el servicio aún no se inicializó,
  /// devuelve la ruta basada en lo que haya (los métodos async ya aseguran la
  /// inicialización antes de leer/escribir, así que en la práctica _cacheDir
  /// ya existe cuando esto se usa).
  File tileFile(int z, int x, int y) {
    final base = _cacheDir?.path ?? '';
    return File('$base/$z/$x/$y.png');
  }

  /// Devuelve los bytes de un tile desde el disco, o `null` si no está cacheado.
  Future<Uint8List?> readTile(int z, int x, int y) async {
    try {
      final dir = await _ensureInit();
      final f = File('${dir.path}/$z/$x/$y.png');
      if (await f.exists()) {
        return await f.readAsBytes();
      }
    } catch (e) {
      debugPrint('TileCache: error leyendo tile $z/$x/$y: $e');
    }
    return null;
  }

  /// Guarda los bytes de un tile en disco.
  Future<void> writeTile(int z, int x, int y, Uint8List bytes) async {
    try {
      final dir = await _ensureInit();
      final f = File('${dir.path}/$z/$x/$y.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('TileCache: error guardando tile $z/$x/$y: $e');
    }
  }

  /// Descarga un solo tile de la red y lo guarda. Devuelve true si tuvo éxito.
  Future<bool> _downloadTile(int z, int x, int y) async {
    // Si ya está, no lo volvemos a bajar.
    if (await tileFile(z, x, y).exists()) return true;
    try {
      final url = tileUrlTemplate
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': userAgent},
      );
      if (resp.statusCode == 200) {
        await writeTile(z, x, y, resp.bodyBytes);
        return true;
      }
      debugPrint('TileCache: tile $z/$x/$y HTTP ${resp.statusCode}');
      return false;
    } catch (e) {
      debugPrint('TileCache: error bajando tile $z/$x/$y: $e');
      return false;
    }
  }

  // ---- Conversión lat/lng <-> tile (estándar slippy map) ----

  static int lonToTileX(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  static int latToTileY(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            (1 << z))
        .floor();
  }

  /// Calcula cuántos tiles implica descargar una región (bounding box) en un
  /// rango de zoom. Útil para advertir al usuario ANTES de descargar.
  static int countTiles({
    required double north,
    required double south,
    required double east,
    required double west,
    required int minZoom,
    required int maxZoom,
  }) {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final xMin = lonToTileX(west, z);
      final xMax = lonToTileX(east, z);
      final yMin = latToTileY(north, z); // norte = y menor
      final yMax = latToTileY(south, z);
      final wTiles = (xMax - xMin).abs() + 1;
      final hTiles = (yMax - yMin).abs() + 1;
      total += wTiles * hTiles;
    }
    return total;
  }

  /// Estima el tamaño en disco de una descarga (tiles × ~promedio por tile).
  /// Un tile PNG de OSM pesa típicamente 10-25 KB. Usamos 18 KB de promedio.
  static String estimateSize(int tileCount) {
    final kb = tileCount * 18;
    if (kb < 1024) return '$kb KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Descarga una región completa. Reporta progreso vía [onProgress]
  /// (descargados, total). Devuelve cuántos se bajaron con éxito.
  ///
  /// Pone un pequeño delay entre tiles para respetar la política de OSM y no
  /// saturar. Se puede cancelar con [cancelToken].
  Future<int> downloadRegion({
    required double north,
    required double south,
    required double east,
    required double west,
    required int minZoom,
    required int maxZoom,
    void Function(int done, int total)? onProgress,
    TileDownloadCancelToken? cancelToken,
  }) async {
    // Aseguramos que el directorio exista ANTES de empezar a bajar. Sin esto,
    // si nadie llamó init(), la descarga tronaba con StateError y se quedaba
    // en 0% (bug observado en Xiaomi y otros).
    await _ensureInit();

    final total = countTiles(
      north: north, south: south, east: east, west: west,
      minZoom: minZoom, maxZoom: maxZoom,
    );
    var done = 0;
    var ok = 0;

    for (var z = minZoom; z <= maxZoom; z++) {
      final xMin = math.min(lonToTileX(west, z), lonToTileX(east, z));
      final xMax = math.max(lonToTileX(west, z), lonToTileX(east, z));
      final yMin = math.min(latToTileY(north, z), latToTileY(south, z));
      final yMax = math.max(latToTileY(north, z), latToTileY(south, z));

      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          if (cancelToken?.isCancelled ?? false) {
            return ok;
          }
          final success = await _downloadTile(z, x, y);
          if (success) ok++;
          done++;
          onProgress?.call(done, total);
          // Delay suave entre tiles (respeto a OSM). 50ms ≈ 20 tiles/s.
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }
    return ok;
  }

  // ---- Gestión de la caché ----

  /// Calcula cuántos tiles hay cacheados y cuánto espacio ocupan.
  Future<({int count, int bytes})> cacheStats() async {
    var count = 0;
    var bytes = 0;
    try {
      final dir = await _ensureInit();
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.png')) {
            count++;
            bytes += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('TileCache: error calculando stats: $e');
    }
    return (count: count, bytes: bytes);
  }

  /// Borra toda la caché de tiles.
  Future<void> clearCache() async {
    try {
      final dir = await _ensureInit();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('TileCache: error limpiando caché: $e');
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// Token simple para cancelar una descarga en curso.
class TileDownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
