import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'event_log_service.dart';

/// Escribe el log de la sesión a disco en dos formatos legibles (sin
/// comprimir, sin cifrar), listos para abrir en Excel/Python o compartir:
///
///  - **JSON** indentado: el registro completo con el payload anidado de cada
///    mensaje. Ideal para reproducir la sesión o analizarla con scripts.
///  - **CSV** plano: una fila por evento con las columnas más usadas para un
///    análisis rápido de señales (lat/lng/accuracy/heading/distancia, bytes).
///
/// Devuelve las rutas de los archivos creados. La pantalla puede luego
/// compartirlos (p. ej. con share_plus) o dejar que el usuario los copie.
class LogExporter {
  /// Carpeta destino. Por defecto el directorio de documentos de la app.
  static Future<Directory> _targetDir() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  /// Exporta a JSON. Devuelve el [File] escrito.
  static Future<File> exportJson(
    EventLogService log, {
    Map<String, dynamic>? sessionMeta,
  }) async {
    final dir = await _targetDir();
    final file = File('${dir.path}/buscamigos_log_${_stamp()}.json');

    final doc = {
      'app': 'buscamigos',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      if (sessionMeta != null) 'session': sessionMeta,
      'stats': {
        'totalEvents': log.count,
        'sent': log.countByDirection(LogDirection.sent),
        'received': log.countByDirection(LogDirection.received),
        'byType': log.countsByType(),
        'totalWireBytes': log.totalWireBytes,
        'totalRawBytes': log.totalRawBytes,
      },
      'events': log.entries.map((e) => e.toJson()).toList(),
    };

    // Indentado para que sea legible a ojo.
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(doc));
    return file;
  }

  /// Exporta a CSV. Aplana los campos de posición más relevantes.
  static Future<File> exportCsv(EventLogService log) async {
    final dir = await _targetDir();
    final file = File('${dir.path}/buscamigos_log_${_stamp()}.csv');

    final sb = StringBuffer();
    sb.writeln([
      'seq', 'timestamp_utc', 'direction', 'type',
      'memberId', 'memberName', 'transport',
      'lat', 'lng', 'accuracy', 'heading', 'rssi', 'rssiDistance',
      'headingConf', 'tilt', 'steps', 'cadence', 'motion',
      'rawBytes', 'wireBytes', 'compressed', 'text',
    ].map(_csv).join(','));

    for (final e in log.entries) {
      final p = e.payload;
      // El payload de 'pos'/'hello' lleva la posición bajo 'pos'/'member.pos';
      // intentamos sacarla de varios lugares de forma tolerante.
      final pos = _extractPosition(p);
      final motion = _extractMotion(p);
      sb.writeln([
        e.seq,
        e.timestamp.toUtc().toIso8601String(),
        e.direction.name,
        e.type,
        e.memberId ?? '',
        e.memberName ?? '',
        e.transport ?? '',
        pos['lat'] ?? '',
        pos['lng'] ?? '',
        pos['acc'] ?? '',
        pos['hdg'] ?? '',
        pos['rssi'] ?? '',
        pos['rd'] ?? '',
        motion['conf'] ?? '',
        motion['tilt'] ?? '',
        motion['steps'] ?? '',
        motion['cad'] ?? '',
        motion['state'] ?? '',
        e.rawBytes,
        e.wireBytes,
        e.compressed,
        _csv((p['text'] ?? p['message'] ?? '').toString()),
      ].map((v) => v is String && v.startsWith('"') ? v : _csv(v.toString())).join(','));
    }

    await file.writeAsString(sb.toString());
    return file;
  }

  static Map<String, dynamic> _extractPosition(Map<String, dynamic> p) {
    if (p['pos'] is Map) return (p['pos'] as Map).cast<String, dynamic>();
    if (p['member'] is Map && (p['member'] as Map)['pos'] is Map) {
      return ((p['member'] as Map)['pos'] as Map).cast<String, dynamic>();
    }
    // Algunos campos pueden venir en la raíz.
    return {
      if (p.containsKey('lat')) 'lat': p['lat'],
      if (p.containsKey('lng')) 'lng': p['lng'],
      if (p.containsKey('acc')) 'acc': p['acc'],
      if (p.containsKey('hdg')) 'hdg': p['hdg'],
      if (p.containsKey('rssi')) 'rssi': p['rssi'],
      if (p.containsKey('rd')) 'rd': p['rd'],
    };
  }

  static Map<String, dynamic> _extractMotion(Map<String, dynamic> p) {
    final m = (p['pos'] is Map) ? (p['pos'] as Map) : p;
    return {
      'conf': m['hc'],
      'tilt': m['tilt'],
      'steps': m['st'],
      'cad': m['cad'],
      'state': m['mo'],
    };
  }

  /// Escapa un campo CSV.
  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
