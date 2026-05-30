import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/database.dart';
import '../models/user.dart';

Router settingsRouter() {
  final router = Router();

  router.get('/<vaultId>', (Request req, String vaultId) {
    final user = req.context['user'] as User;
    if (!_vaultBelongsToUser(vaultId, user.id)) {
      return _json({'error': 'Vault not found'}, 404);
    }
    return _json(_getOrCreate(vaultId), 200);
  });

  router.put('/<vaultId>', (Request req, String vaultId) async {
    final user = req.context['user'] as User;
    if (!_vaultBelongsToUser(vaultId, user.id)) {
      return _json({'error': 'Vault not found'}, 404);
    }
    final body = await _parseBody(req);
    if (body == null) return _json({'error': 'Invalid JSON'}, 400);

    final templateFolder = body['templateFolder'] as String? ?? '_templates';
    final defaultNoteFolder = body['defaultNoteFolder'] as String? ?? '';
    final autoPushOnClose = (body['autoPushOnClose'] as bool?) == true ? 1 : 0;

    db.execute('''
      INSERT INTO vault_settings (vault_id, template_folder, default_note_folder, auto_push_on_close)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(vault_id) DO UPDATE SET
        template_folder = excluded.template_folder,
        default_note_folder = excluded.default_note_folder,
        auto_push_on_close = excluded.auto_push_on_close
    ''', [vaultId, templateFolder, defaultNoteFolder, autoPushOnClose]);

    return _json(_getOrCreate(vaultId), 200);
  });

  return router;
}

bool _vaultBelongsToUser(String vaultId, String userId) {
  final rows = db.select(
    'SELECT id FROM vaults WHERE id = ? AND user_id = ?',
    [vaultId, userId],
  );
  return rows.isNotEmpty;
}

Map<String, dynamic> _getOrCreate(String vaultId) {
  final rows = db.select(
    'SELECT * FROM vault_settings WHERE vault_id = ?',
    [vaultId],
  );
  if (rows.isEmpty) {
    return {'templateFolder': '_templates', 'defaultNoteFolder': '', 'autoPushOnClose': false};
  }
  return {
    'templateFolder': rows.first['template_folder'],
    'defaultNoteFolder': rows.first['default_note_folder'],
    'autoPushOnClose': (rows.first['auto_push_on_close'] as int?) == 1,
  };
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
