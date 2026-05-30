// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class TokenStorage {
  static const _key = 'ov_token';
  static const _persistKey = 'ov_remember';

  /// Saves [token] to localStorage (persistent) or sessionStorage (session-only).
  static void save(String token, {bool persistent = false}) {
    if (persistent) {
      html.window.localStorage[_key] = token;
      html.window.localStorage[_persistKey] = '1';
      html.window.sessionStorage.remove(_key);
    } else {
      html.window.sessionStorage[_key] = token;
      html.window.localStorage.remove(_key);
      html.window.localStorage.remove(_persistKey);
    }
  }

  /// Returns the stored token (localStorage first, then sessionStorage).
  static String? load() {
    return html.window.localStorage[_key] ??
        html.window.sessionStorage[_key];
  }

  /// Whether the stored token is in localStorage (persists across sessions).
  static bool get isPersistent =>
      html.window.localStorage[_persistKey] == '1';

  static void clear() {
    html.window.localStorage.remove(_key);
    html.window.localStorage.remove(_persistKey);
    html.window.sessionStorage.remove(_key);
  }
}
