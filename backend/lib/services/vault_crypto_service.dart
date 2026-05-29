import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// Vault encryption at rest — AES-256-GCM with PBKDF2-derived key.
// The key is derived from the user's password + per-user encryption_salt,
// held only in RAM, never written to disk.
//
// NOTE: The public API is ready for Phase 7 deployment.
// In the current backend, vault files are stored unencrypted (plain git clones).
// To enable encryption:
//  1. Call deriveKey() after login, store in a session cache.
//  2. Wrap readFile/writeFile in encryptFile/decryptFile.
//  3. On password change, re-encrypt all files.

final _rng = Random.secure();

Uint8List deriveKey(String password, String saltBase64) {
  final salt = base64Url.decode(saltBase64);
  final params = Pbkdf2Parameters(Uint8List.fromList(salt), 310000, 32);
  final mac = HMac(SHA256Digest(), 64);
  final kdf = PBKDF2KeyDerivator(mac)..init(params);
  return kdf.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List encryptFile(Uint8List plaintext, Uint8List key, String aad) {
  final nonce = _randomBytes(12);
  final params = AEADParameters(KeyParameter(key), 128, nonce, utf8.encode(aad));
  final cipher = GCMBlockCipher(AESEngine())..init(true, params);
  final ciphertext = cipher.process(plaintext);
  // Layout: nonce(12) | ciphertext+tag
  return Uint8List.fromList([...nonce, ...ciphertext]);
}

Uint8List decryptFile(Uint8List blob, Uint8List key, String aad) {
  if (blob.length < 12) throw const FormatException('Invalid encrypted blob');
  final nonce = blob.sublist(0, 12);
  final ciphertext = blob.sublist(12);
  final params = AEADParameters(KeyParameter(key), 128, nonce, utf8.encode(aad));
  final cipher = GCMBlockCipher(AESEngine())..init(false, params);
  return cipher.process(ciphertext);
}

Uint8List _randomBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rng.nextInt(256);
  }
  return b;
}

// Re-encrypt all files in a vault directory after password change
Future<void> reEncryptVault(String dirPath, Uint8List oldKey, Uint8List newKey) async {
  final dir = Directory(dirPath);
  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.md.enc')) continue;
    final rel = entity.path.substring(dirPath.length + 1);
    final blob = await entity.readAsBytes();
    final plaintext = decryptFile(blob, oldKey, rel);
    final reEncrypted = encryptFile(plaintext, newKey, rel);
    await entity.writeAsBytes(reEncrypted);
  }
}
