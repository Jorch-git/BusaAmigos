import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SavedGroup {
  final String groupCode;
  final String groupName;
  final String displayName;
  final String selfId;
  final bool wasHost;

  const SavedGroup({
    required this.groupCode,
    required this.groupName,
    required this.displayName,
    required this.selfId,
    required this.wasHost,
  });

  Map<String, dynamic> toJson() => {
        'groupCode': groupCode,
        'groupName': groupName,
        'displayName': displayName,
        'selfId': selfId,
        'wasHost': wasHost,
      };

  factory SavedGroup.fromJson(Map<String, dynamic> json) => SavedGroup(
        groupCode: json['groupCode'] as String,
        groupName: json['groupName'] as String,
        displayName: json['displayName'] as String,
        selfId: json['selfId'] as String,
        wasHost: json['wasHost'] as bool,
      );
}

class GroupStorage {
  static const _fileName = 'buscamigos_last_group.json';

  Future<File> _storageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<SavedGroup?> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return SavedGroup.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SavedGroup group) async {
    final file = await _storageFile();
    await file.writeAsString(jsonEncode(group.toJson()));
  }

  Future<void> clear() async {
    try {
      final file = await _storageFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignoramos errores de borrado.
    }
  }
}
