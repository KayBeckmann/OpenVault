import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/auth_service.dart';

final _authService = AuthService();

Middleware requireAuth() {
  return (Handler inner) {
    return (Request request) async {
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({'error': 'Authorization required'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final token = authHeader.substring(7);
      final user = _authService.getUserFromToken(token);
      if (user == null) {
        return Response(
          401,
          body: jsonEncode({'error': 'Invalid or expired token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Attach user to request context
      final updated = request.change(context: {'user': user});
      return inner(updated);
    };
  };
}
