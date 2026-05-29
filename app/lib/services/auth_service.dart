import 'package:flutter/foundation.dart';
import 'api_client.dart';

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
    _api.setToken(result['token'] as String?);
    _currentUser = result['user'] as Map<String, dynamic>?;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final result = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
    });
    _api.setToken(result['token'] as String?);
    _currentUser = result['user'] as Map<String, dynamic>?;
    notifyListeners();
  }

  void logout() {
    _api.setToken(null);
    _currentUser = null;
    notifyListeners();
  }
}
