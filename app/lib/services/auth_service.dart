import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'token_storage.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._();
  AuthService._();
  factory AuthService() => _instance;

  final _api = ApiClient();
  Map<String, dynamic>? _currentUser;

  bool get isAuthenticated => _api.isAuthenticated;
  Map<String, dynamic>? get currentUser => _currentUser;

  Future<void> register(String email, String password) async {
    final result = await _api.post('/api/auth/register', {
      'email': email,
      'password': password,
    });
    final token = result['token'] as String?;
    _api.setToken(token);
    _currentUser = result['user'] as Map<String, dynamic>?;
    notifyListeners();
  }

  Future<void> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    final result = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
      'rememberMe': rememberMe,
    });
    final token = result['token'] as String?;
    _api.setToken(token);
    if (token != null) TokenStorage.save(token, persistent: rememberMe);
    _currentUser = result['user'] as Map<String, dynamic>?;
    notifyListeners();
  }

  /// On web startup: tries to restore session from storage.
  /// For remember-me tokens: calls /refresh to get a fresh 7-day token.
  /// Returns true if session was restored successfully.
  Future<bool> tryRestoreSession() async {
    if (!kIsWeb) return false;
    final stored = TokenStorage.load();
    if (stored == null) return false;

    try {
      _api.setToken(stored);
      if (TokenStorage.isPersistent) {
        // Rolling refresh: get new 7-day token
        final result = await _api.post('/api/auth/refresh', {});
        final newToken = result['token'] as String?;
        if (newToken != null) {
          _api.setToken(newToken);
          TokenStorage.save(newToken, persistent: true);
        }
        _currentUser = result['user'] as Map<String, dynamic>?;
      } else {
        // Session-only: just verify the token is still valid
        final user = await _api.get('/api/auth/me');
        _currentUser = user;
      }
      notifyListeners();
      return true;
    } catch (_) {
      // Token expired or invalid — clear storage and require re-login
      TokenStorage.clear();
      _api.setToken(null);
      return false;
    }
  }

  void logout() {
    _api.setToken(null);
    _currentUser = null;
    TokenStorage.clear();
    notifyListeners();
  }
}
