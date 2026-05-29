import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:backend/routes/auth_routes.dart';
import 'package:backend/routes/health_routes.dart';
import 'package:backend/routes/ssh_key_routes.dart';
import 'package:backend/routes/vault_routes.dart';
import 'package:backend/routes/file_routes.dart';
import 'package:backend/middleware/auth_middleware.dart';

void main(List<String> args) async {
  final ip = InternetAddress.anyIPv4;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final router = Router();

  router.mount('/health', healthRouter().call);
  router.mount('/api/auth/', authRouter().call);
  router.mount('/api/', Pipeline().addMiddleware(requireAuth()).addHandler(_protectedRouter().call));

  final handler = Pipeline()
      .addMiddleware(corsHeaders())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await serve(handler, ip, port);
  print('OpenVault backend listening on port ${server.port}');
}

Router _protectedRouter() {
  final router = Router();

  router.get('/status', (Request req) async => Response.ok(
    jsonEncode({'status': 'authenticated'}),
    headers: {'content-type': 'application/json'},
  ));

  router.mount('/ssh-keys/', sshKeyRouter().call);
  router.mount('/vaults/', vaultRouter().call);
  router.mount('/files/', fileRouter().call);

  return router;
}
