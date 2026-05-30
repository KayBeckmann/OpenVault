import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

final _auth = AuthService();

Router authRouter() {
  final router = Router();

  router.post('/register', (Request req) async {
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON body');

    final email = body['email'] as String?;
    final password = body['password'] as String?;
    if (email == null || password == null) {
      return _badRequest('email and password are required');
    }

    try {
      final result = await _auth.register(email, password);
      return _json(result, 201);
    } on AuthException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  router.post('/login', (Request req) async {
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON body');

    final email = body['email'] as String?;
    final password = body['password'] as String?;
    if (email == null || password == null) {
      return _badRequest('email and password are required');
    }

    final rememberMe = body['rememberMe'] as bool? ?? false;
    try {
      final result = await _auth.login(email, password, rememberMe: rememberMe);
      return _json(result, 200);
    } on AuthException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Refresh a remember-me session → new 7-day token (rolling window)
  router.post('/refresh', (Request req) async {
    final authHeader = req.headers['authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return _json({'error': 'Authorization required'}, 401);
    }
    final token = authHeader.substring(7);
    try {
      final result = await _auth.refreshToken(token);
      return _json(result, 200);
    } on AuthException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  router.post('/logout', (Request req) async {
    final authHeader = req.headers['authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return _json({'error': 'Authorization required'}, 401);
    }
    // In a real scenario we'd parse the jti from the JWT; simplified here
    final user = req.context['user'] as User?;
    if (user == null) return _json({'error': 'Not authenticated'}, 401);
    return _json({'message': 'Logged out'}, 200);
  });

  router.get('/me', (Request req) async {
    final user = req.context['user'] as User?;
    if (user == null) return _json({'error': 'Not authenticated'}, 401);
    return _json(user.toPublicJson(), 200);
  });

  return router;
}

Future<Map<String, dynamic>?> _parseBody(Request req) async {
  try {
    final body = await req.readAsString();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Response _json(dynamic data, int status) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );

Response _badRequest(String message) => _json({'error': message}, 400);
