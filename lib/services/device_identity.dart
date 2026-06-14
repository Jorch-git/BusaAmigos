import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Identidad estable del dispositivo, persistida en disco.
///
/// PROBLEMA QUE RESUELVE: antes, cada vez que el usuario creaba o se unía a
/// un grupo se generaba un `selfId` aleatorio nuevo. Si te desconectabas y
/// te volvías a unir tecleando el código, obtenías un ID distinto, así que
/// para los demás celulares aparecías como "otra persona" con el mismo
/// nombre → veías tu nombre duplicado (uno idle, uno activo).
///
/// SOLUCIÓN: un identificador único que se genera UNA sola vez por
/// instalación de la app y se reutiliza siempre. Es el equivalente lógico a
/// una "MAC estable" para tu dispositivo dentro de Buscamigos. Mientras no
/// reinstales la app ni borres sus datos, tu ID es el mismo.
///
/// Nota sobre por qué no usamos la MAC real: Android (desde la versión 6) y
/// iOS NO permiten a las apps leer la MAC de WiFi/Bluetooth por privacidad
/// (devuelven un valor falso fijo como 02:00:00:00:00:00). Por eso generamos
/// nuestro propio identificador estable, que cumple la misma función sin
/// depender de hardware ni de permisos especiales.
class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  static const _fileName = 'buscamigos_device_id.json';
  static const _uuid = Uuid();

  String? _deviceId;

  /// El ID estable del dispositivo. Llama a [load] antes de usarlo.
  String? get deviceId => _deviceId;

  /// Carga el ID desde disco. Si no existe, genera uno nuevo y lo guarda.
  /// Devuelve el ID (nuevo o existente).
  Future<String> load() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final saved = data['deviceId'] as String?;
        if (saved != null && saved.isNotEmpty) {
          _deviceId = saved;
          debugPrint('DeviceIdentity: ID cargado: $saved');
          return saved;
        }
      }
    } catch (e) {
      debugPrint('DeviceIdentity: error cargando, genero uno nuevo: $e');
    }

    // No había ID válido: generamos uno y lo guardamos.
    final fresh = _uuid.v4();
    _deviceId = fresh;
    await _persist(fresh);
    debugPrint('DeviceIdentity: ID nuevo generado: $fresh');
    return fresh;
  }

  Future<void> _persist(String id) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'deviceId': id}));
    } catch (e) {
      debugPrint('DeviceIdentity: error guardando: $e');
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
