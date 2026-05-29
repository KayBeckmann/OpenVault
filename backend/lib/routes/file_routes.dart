import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models/user.dart';
import '../services/file_service.dart';

final _files = FileService();

Router fileRouter() {
  final router = Router();

  // File tree
  router.get('/<vaultId>/tree', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    try {
      return _json(_files.getTree(user, vaultId), 200);
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Read file
  router.get('/<vaultId>/file', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    final path = req.url.queryParameters['path'] ?? '';
    try {
      final content = _files.readFile(user, vaultId, path);
      return Response.ok(content, headers: {'content-type': 'text/plain; charset=utf-8'});
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Write file
  router.put('/<vaultId>/file', (Request req, String vaultId) async {
    final user = req.context['user'] as User;
    final body = await _parseBody(req);
    if (body == null) return _badRequest('Invalid JSON body');
    final path = body['path'] as String?;
    final content = body['content'] as String?;
    if (path == null || content == null) return _badRequest('path and content required');
    try {
      _files.writeFile(user, vaultId, path, content);
      return _json({'message': 'File saved'}, 200);
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Delete file
  router.delete('/<vaultId>/file', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    final path = req.url.queryParameters['path'] ?? '';
    try {
      _files.deleteFile(user, vaultId, path);
      return _json({'message': 'File deleted'}, 200);
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Create folder
  router.post('/<vaultId>/folder', (Request req, String vaultId) async {
    final user = req.context['user'] as User;
    final body = await _parseBody(req);
    final path = body?['path'] as String?;
    if (path == null) return _badRequest('path required');
    try {
      _files.createFolder(user, vaultId, path);
      return _json({'message': 'Folder created'}, 201);
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Search
  router.get('/<vaultId>/search', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    final query = req.url.queryParameters['q'] ?? '';
    try {
      final results = _files.searchFiles(user, vaultId, query);
      return _json(results, 200);
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Tags — list all
  router.get('/<vaultId>/tags', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    try {
      return _json(_files.getTags(user, vaultId), 200);
    } on FileException catch (e) {
      return _json({'error': e.message}, e.statusCode);
    }
  });

  // Tags — filter files
  router.get('/<vaultId>/tags/filter', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    final tagParam = req.url.queryParameters['tags'] ?? '';
    final operator = req.url.queryParameters['op'] ?? 'AND';
    final tags = tagParam.split(',').where((t) => t.isNotEmpty).toList();
    try {
      final results = _files.filterByTags(user, vaultId, tags, operator);
      return _json(results, 200);
    } on FileException catch (e) {
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
