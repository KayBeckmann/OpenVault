import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Persists the add-on enabled-map in a JSON file in the app support directory.
class AddonStore {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/openvault_addons.json');
  }

  static Future<Map<String, bool>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v == true));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, bool> enabled) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(enabled));
    } catch (_) {
      // Persistence is best-effort; ignore write failures.
    }
  }
}
