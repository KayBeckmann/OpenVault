// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

/// Persists the add-on enabled-map in browser localStorage.
class AddonStore {
  static const _key = 'ov_addons';

  static Future<Map<String, bool>> load() async {
    final raw = html.window.localStorage[_key];
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v == true));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, bool> enabled) async {
    html.window.localStorage[_key] = jsonEncode(enabled);
  }
}
