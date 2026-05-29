import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models/user.dart';
import '../services/ssh_key_service.dart';

final _sshService = SshKeyService();

Router sshKeyRouter() {
  final router = Router();

  // List all SSH keys for the authenticated user
  router.get('/', (Request req) {
    final user = req.context['user'] as User;
    final keys = _sshService.listKeys(user);
    return _json(keys, 200);
  });

  // Generate a new SSH keypair
  router.post('/', (Request req) async {
    final user = req.context['user'] as User;
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON body');

    final label = body['label'] as String?;
    if (label == null) return _badRequest('label is required');

    try {
      final key = await _sshService.generateKey(user, label);
      return _json(key, 201);
    } on SshKeyException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Get public key by ID
  router.get('/<id>', (Request req, String id) {
    final user = req.context['user'] as User;
    try {
      final key = _sshService.getPublicKey(user, id);
      return _json(key, 200);
    } on SshKeyException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Delete a key
  router.delete('/<id>', (Request req, String id) {
    final user = req.context['user'] as User;
    try {
      _sshService.deleteKey(user, id);
      return _json({'message': 'Key deleted'}, 200);
    } on SshKeyException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  return router;
}

Future<Map<String, dynamic>?> _parseBody(Request req) async {
  try {
    return jsonDecode(await req.readAsString()) as Map<String, dynamic>;
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
