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

    // Try ssh-keygen (fast, if available); fall back to pure-Dart generation.
    try {
      return await _generateViaSshKeygen(user, label);
    } on SshKeyException {
      rethrow;
    } catch (_) {
      return _generateViaDart(user, label);
    }
  }

  Future<Map<String, dynamic>> _generateViaSshKeygen(User user, String label) async {
    final dir = await Directory.systemTemp.createTemp('openvault_keygen_');
    final keyPath = '${dir.path}/key';

    try {
      final result = await Process.run(
        '/usr/bin/ssh-keygen',
        ['-t', 'rsa', '-b', '4096', '-m', 'PEM', '-f', keyPath, '-N', '', '-C', label.trim()],
        // Provide explicit HOME so ssh-keygen doesn't look for /nonexistent/.ssh
        environment: {...Platform.environment, 'HOME': dir.path},
      );

      if (result.exitCode != 0) {
        throw SshKeyException('ssh-keygen failed: ${result.stderr}', 500);
      }

      final publicKey = (await File('$keyPath.pub').readAsString()).trim();
      final privateKeyPem = (await File(keyPath).readAsString()).trim();
      return _storeKey(user, label, publicKey, privateKeyPem);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  // Pure-Dart RSA-4096 generation — used when ssh-keygen is unavailable.
  Map<String, dynamic> _generateViaDart(User user, String label) {
    final secureRandom = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => _rng.nextInt(256)))));

    final gen = RSAKeyGenerator()
      ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), 4096, 64), secureRandom));

    final pair = gen.generateKeyPair() as AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>;
    final pub = pair.publicKey;
    final priv = pair.privateKey;

    final privatePem = _rsaPrivKeyPkcs1Pem(priv, pub.publicExponent!);
    final publicStr = _rsaPubKeySsh(pub, label.trim());
    return _storeKey(user, label, publicStr, privatePem);
  }

  Map<String, dynamic> _storeKey(User user, String label, String publicKey, String privateKeyPem) {
    final encryptedPrivateKey = _encryptPrivateKey(privateKeyPem);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO ssh_keys (id, user_id, label, public_key, private_key_enc, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [id, user.id, label.trim(), publicKey.trim(), encryptedPrivateKey, now],
    );
    return {'id': id, 'label': label.trim(), 'publicKey': publicKey.trim(), 'createdAt': now};
  }

  // Serialize RSA private key as PKCS#1 PEM (-----BEGIN RSA PRIVATE KEY-----)
  static String _rsaPrivKeyPkcs1Pem(RSAPrivateKey k, BigInt e) {
    final n = k.modulus!;
    final d = k.privateExponent!;
    final p = k.p!;
    final q = k.q!;
    final dp = d % (p - BigInt.one);
    final dq = d % (q - BigInt.one);
    final qInv = q.modInverse(p);

    final der = _derSeq([
      _derInt(BigInt.zero), _derInt(n), _derInt(e), _derInt(d),
      _derInt(p), _derInt(q), _derInt(dp), _derInt(dq), _derInt(qInv),
    ]);

    final b64 = base64.encode(der);
    final sb = StringBuffer('-----BEGIN RSA PRIVATE KEY-----\n');
    for (var i = 0; i < b64.length; i += 64) {
      sb.writeln(b64.substring(i, (i + 64).clamp(0, b64.length)));
    }
    sb.write('-----END RSA PRIVATE KEY-----\n');
    return sb.toString();
  }

  // Serialize RSA public key as OpenSSH authorized_keys line
  static String _rsaPubKeySsh(RSAPublicKey k, String comment) {
    final type = utf8.encode('ssh-rsa');
    final e = _sshMpint(k.publicExponent!);
    final n = _sshMpint(k.modulus!);
    final blob = [
      ..._u32x(type.length), ...type,
      ..._u32x(e.length),    ...e,
      ..._u32x(n.length),    ...n,
    ];
    return 'ssh-rsa ${base64.encode(blob)} $comment';
  }

  // DER helpers
  static Uint8List _derSeq(List<Uint8List> items) {
    final body = Uint8List.fromList(items.expand((e) => e).toList());
    return Uint8List.fromList([0x30, ..._derLen(body.length), ...body]);
  }

  static Uint8List _derInt(BigInt v) {
    var b = _bigIntBytes(v);
    if (b.isNotEmpty && (b[0] & 0x80) != 0) b = Uint8List.fromList([0, ...b]);
    return Uint8List.fromList([0x02, ..._derLen(b.length), ...b]);
  }

  static List<int> _derLen(int n) {
    if (n < 128) return [n];
    if (n < 256) return [0x81, n];
    if (n < 65536) return [0x82, n >> 8, n & 0xff];
    return [0x83, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
  }

  static Uint8List _bigIntBytes(BigInt v) {
    if (v == BigInt.zero) return Uint8List(1);
    var hex = v.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return Uint8List.fromList(List.generate(hex.length ~/ 2, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
  }

  // SSH mpint: big-endian bytes with leading 0x00 if high bit set
  static Uint8List _sshMpint(BigInt v) {
    var b = _bigIntBytes(v);
    if (b.isNotEmpty && (b[0] & 0x80) != 0) b = Uint8List.fromList([0, ...b]);
    return b;
  }

  static List<int> _u32x(int v) => [v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff];

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
    final rawEnv = utf8.encode(envKey);
    final keyBytes = Uint8List(32);
    for (var i = 0; i < 32; i++) keyBytes[i] = i < rawEnv.length ? rawEnv[i] : 0x21;
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
