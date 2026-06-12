import 'package:flutter/foundation.dart';

/// Dirección de un evento respecto a este dispositivo.
enum LogDirection { sent, received, system }

/// Una entrada del log. Guarda el contenido YA DESCIFRADO y legible (el
/// requerimiento de Jorge: el log final no va comprimido ni cifrado), más
/// métricas de tamaño en el cable para analizar el ahorro de datos.
class LogEntry {
  final int seq;
  final DateTime timestamp;
  final LogDirection direction;

  /// Tipo de mensaje: hello, pos, chat, sos, sosResponse, leave, system...
  final String type;

  /// Id y nombre del miembro origen/destino (cuando aplica).
  final String? memberId;
  final String? memberName;

  /// Contenido legible (mapa descifrado, o texto para eventos de sistema).
  final Map<String, dynamic> payload;

  /// Métricas de tamaño. Para eventos de sistema quedan en 0.
  final int rawBytes; // JSON sin comprimir
  final int wireBytes; // blob cifrado en el cable
  final bool compressed;

  /// Transporte por el que viajó (nearby, bridgefy, fake, relay).
  final String? transport;

  const LogEntry({
    required this.seq,
    required this.timestamp,
    required this.direction,
    required this.type,
    required this.payload,
    this.memberId,
    this.memberName,
    this.rawBytes = 0,
    this.wireBytes = 0,
    this.compressed = false,
    this.transport,
  });

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'ts': timestamp.toUtc().toIso8601String(),
        'dir': direction.name,
        'type': type,
        if (memberId != null) 'memberId': memberId,
        if (memberName != null) 'memberName': memberName,
        if (transport != null) 'transport': transport,
        'rawBytes': rawBytes,
        'wireBytes': wireBytes,
        'compressed': compressed,
        'payload': payload,
      };
}

/// Acumula el historial completo de la sesión para revisarlo/exportarlo en la
/// última pantalla. Vive en memoria (la sesión de un festival cabe de sobra);
/// tiene un tope para no crecer sin límite.
class EventLogService extends ChangeNotifier {
  EventLogService({this.maxEntries = 50000});

  final int maxEntries;
  final List<LogEntry> _entries = [];
  int _seq = 0;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  int get count => _entries.length;

  void _add(LogEntry e) {
    _entries.add(e);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  /// Registra un mensaje saliente (ya conoces el contenido en claro porque tú
  /// lo creaste; las métricas vienen del [PayloadCodec]).
  void logSent({
    required String type,
    required Map<String, dynamic> payload,
    String? memberId,
    String? memberName,
    int rawBytes = 0,
    int wireBytes = 0,
    bool compressed = false,
    String? transport,
  }) {
    _add(LogEntry(
      seq: _seq++,
      timestamp: DateTime.now(),
      direction: LogDirection.sent,
      type: type,
      payload: payload,
      memberId: memberId,
      memberName: memberName,
      rawBytes: rawBytes,
      wireBytes: wireBytes,
      compressed: compressed,
      transport: transport,
    ));
  }

  /// Registra un mensaje entrante, después de descifrarlo.
  void logReceived({
    required String type,
    required Map<String, dynamic> payload,
    String? memberId,
    String? memberName,
    int rawBytes = 0,
    int wireBytes = 0,
    bool compressed = false,
    String? transport,
  }) {
    _add(LogEntry(
      seq: _seq++,
      timestamp: DateTime.now(),
      direction: LogDirection.received,
      type: type,
      payload: payload,
      memberId: memberId,
      memberName: memberName,
      rawBytes: rawBytes,
      wireBytes: wireBytes,
      compressed: compressed,
      transport: transport,
    ));
  }

  /// Eventos de sistema (conexión, anclaje GPS, cambios de estado, errores).
  void logSystem(String message, {Map<String, dynamic>? extra}) {
    _add(LogEntry(
      seq: _seq++,
      timestamp: DateTime.now(),
      direction: LogDirection.system,
      type: 'system',
      payload: {'message': message, if (extra != null) ...extra},
    ));
  }

  void clear() {
    _entries.clear();
    _seq = 0;
    notifyListeners();
  }

  // ---- Estadísticas para la cabecera del resumen ----

  Map<String, int> countsByType() {
    final m = <String, int>{};
    for (final e in _entries) {
      m[e.type] = (m[e.type] ?? 0) + 1;
    }
    return m;
  }

  int get totalWireBytes =>
      _entries.fold(0, (s, e) => s + e.wireBytes);

  int get totalRawBytes =>
      _entries.fold(0, (s, e) => s + e.rawBytes);

  /// Ahorro por compresión [0..1]. 0.6 = se mandó 60% de lo que pesaría plano.
  double get compressionRatio {
    final raw = totalRawBytes;
    if (raw == 0) return 1;
    // Comparamos cuerpo comprimido vs crudo (wire incluye overhead de cifrado).
    final comp = _entries.fold<int>(
        0, (s, e) => s + (e.compressed ? e.wireBytes : e.rawBytes));
    return comp / raw;
  }

  int countByDirection(LogDirection d) =>
      _entries.where((e) => e.direction == d).length;
}
