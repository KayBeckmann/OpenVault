import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/database.dart';

Router healthRouter() {
  final router = Router();

  router.get('/', (Request req) {
    try {
      db.select('SELECT 1');
      return Response.ok(
        jsonEncode({'status': 'ok', 'database': 'connected'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'database': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  });

  return router;
}
