import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

final _random = Random.secure();

String generateSalt([int bytes = 16]) {
  final b = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    b[i] = _random.nextInt(256);
  }
  return base64Url.encode(b);
}

// PBKDF2-SHA256 — 310 000 iterations per OWASP 2023 recommendation
String hashPassword(String password, String saltBase64) {
  final salt = base64Url.decode(saltBase64);
  final dk = _pbkdf2(utf8.encode(password), salt, 310000, 32);
  return base64Url.encode(dk);
}

bool verifyPassword(String password, String saltBase64, String hashBase64) {
  final computed = hashPassword(password, saltBase64);
  // constant-time comparison
  final a = base64Url.decode(computed);
  final b = base64Url.decode(hashBase64);
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int keyLength) {
  final params = Pbkdf2Parameters(Uint8List.fromList(salt), iterations, keyLength);
  final mac = HMac(SHA256Digest(), 64);
  final kdf = PBKDF2KeyDerivator(mac)..init(params);
  return kdf.process(Uint8List.fromList(password));
}
