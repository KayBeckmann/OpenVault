import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models/user.dart';
import '../services/git_service.dart';

final _git = GitService();

Router vaultRouter() {
  final router = Router();

  router.get('/', (Request req) {
    final user = req.context['user'] as User;
    final vaults = _git.listVaults(user).map((v) => v.toJson()).toList();
    return _json(vaults, 200);
  });

  router.post('/clone', (Request req) async {
    final user = req.context['user'] as User;
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON body');

    final name = body['name'] as String?;
    final remoteUrl = body['remoteUrl'] as String?;
    final sshKeyId = body['sshKeyId'] as String?;

    if (name == null || remoteUrl == null) {
      return _badRequest('name and remoteUrl are required');
    }

    try {
      final vault = await _git.cloneVault(user, name, remoteUrl, sshKeyId: sshKeyId);
      return _json(vault.toJson(), 201);
    } on GitException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  router.post('/<id>/pull', (Request req, String id) async {
    final user = req.context['user'] as User;
    try {
      final result = await _git.pullVault(user, id);
      return _json(result, 200);
    } on GitException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  router.post('/<id>/push', (Request req, String id) async {
    final user = req.context['user'] as User;
    final body = await _parseBody(req);
    final commitMessage = body?['commitMessage'] as String? ?? '';
    try {
      final result = await _git.pushVault(user, id, commitMessage);
      return _json(result, 200);
    } on GitException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  router.get('/<id>/diff', (Request req, String id) async {
    final user = req.context['user'] as User;
    try {
      final result = await _git.getDiff(user, id);
      return _json(result, 200);
    } on GitException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  router.delete('/<id>', (Request req, String id) {
    final user = req.context['user'] as User;
    try {
      _git.deleteVault(user, id);
      return _json({'message': 'Vault deleted'}, 200);
    } on GitException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  return router;
}

Future<Map<String, dynamic>?> _parseBody(Request req) async {
  try {
    final s = await req.readAsString();
    if (s.isEmpty) return {};
    return jsonDecode(s) as Map<String, dynamic>;
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
