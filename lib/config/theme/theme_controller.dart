import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Controla el modo de tema (claro/oscuro) y lo persiste a disco.
/// Es un ChangeNotifier para que MaterialApp reaccione al cambio.
class ThemeController extends ChangeNotifier {
  static const _fileName = 'buscamigos_theme.json';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// Carga la preferencia guardada. Si no hay, queda en oscuro (default).
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final saved = data['mode'] as String?;
      _mode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.dark,
      };
      notifyListeners();
    } catch (_) {
      // Si falla, nos quedamos con el default.
    }
  }

  /// Alterna entre claro y oscuro.
  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await _save();
  }

  /// Setea un modo específico.
  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      final modeStr = _mode == ThemeMode.light ? 'light' : 'dark';
      await file.writeAsString(jsonEncode({'mode': modeStr}));
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
