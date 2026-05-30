import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:pointycastle/export.dart';
import '../db/database.dart';
import '../models/user.dart';

const _uuid = Uuid();
final _rng = Random.secure();

class SshKeyService {
  List<Map<String, dynamic>> listKeys(User user) {
    final rows = db.select(
      'SELECT id, label, public_key, created_at FROM ssh_keys WHERE user_id = ? ORDER BY created_at DESC',
      [user.id],
    );
    return rows
        .map((r) => {
              'id': r['id'],
              'label': r['label'],
              'publicKey': r['public_key'],
              'createdAt': r['created_at'],
            })
        .toList();
  }

  Future<Map<String, dynamic>> generateKey(User user, String label) async {
    if (label.trim().isEmpty) throw SshKeyException('Label is required', 400);

    final dir = await Directory.systemTemp.createTemp('openvault_keygen_');
    final keyPath = '${dir.path}/key';

    try {
      final result = await Process.run('ssh-keygen', [
        '-t', 'rsa', '-b', '4096',
        '-m', 'PEM',             // classic PEM format — widest SSH client compatibility
        '-f', keyPath,
        '-N', '',                // no passphrase — we encrypt ourselves
        '-C', label.trim(),
      ]);

      if (result.exitCode != 0) {
        throw SshKeyException('Key generation failed: ${result.stderr}', 500);
      }

      final publicKey = await File('$keyPath.pub').readAsString();
      final privateKeyPem = await File(keyPath).readAsString();
      final encryptedPrivateKey = _encryptPrivateKey(privateKeyPem.trim());

      final id = _uuid.v4();
      final now = DateTime.now().toUtc().toIso8601String();

      db.execute(
        'INSERT INTO ssh_keys (id, user_id, label, public_key, private_key_enc, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, user.id, label.trim(), publicKey.trim(), encryptedPrivateKey, now],
      );

      return {
        'id': id,
        'label': label.trim(),
        'publicKey': publicKey.trim(),
        'createdAt': now,
      };
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Map<String, dynamic> getPublicKey(User user, String keyId) {
    final rows = db.select(
      'SELECT id, label, public_key, created_at FROM ssh_keys WHERE id = ? AND user_id = ?',
      [keyId, user.id],
    );
    if (rows.isEmpty) throw SshKeyException('SSH key not found', 404);
    final r = rows.first;
    return {
      'id': r['id'],
      'label': r['label'],
      'publicKey': r['public_key'],
      'createdAt': r['created_at'],
    };
  }

  void deleteKey(User user, String keyId) {
    final rows = db.select(
      'SELECT id FROM ssh_keys WHERE id = ? AND user_id = ?',
      [keyId, user.id],
    );
    if (rows.isEmpty) throw SshKeyException('SSH key not found', 404);
    db.execute('DELETE FROM ssh_keys WHERE id = ?', [keyId]);
  }

  Uint8List _secureBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  String _encryptPrivateKey(String pem) {
    final envKey = Platform.environment['ENCRYPTION_KEY'] ?? 'dev-key-32-bytes-pad-to-length!!';
    final keyBytes = Uint8List.fromList(utf8.encode(envKey.padRight(32, '!').substring(0, 32)));
    final nonce = _secureBytes(12);
    final params = AEADParameters(KeyParameter(keyBytes), 128, nonce, Uint8List(0));
    final cipher = GCMBlockCipher(AESEngine())..init(true, params);
    final plaintext = Uint8List.fromList(utf8.encode(pem));
    final ciphertext = cipher.process(plaintext);
    return base64.encode(Uint8List.fromList([...nonce, ...ciphertext]));
  }
}

class SshKeyException implements Exception {
  final String message;
  final int statusCode;
  const SshKeyException(this.message, this.statusCode);
}
