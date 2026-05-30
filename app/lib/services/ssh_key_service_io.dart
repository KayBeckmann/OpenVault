import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

class SshKeyInfo {
  final String privateKeyPath;
  final String publicKey;
  final bool isSystemKey;
  const SshKeyInfo({required this.privateKeyPath, required this.publicKey, required this.isSystemKey});
}

class SshKeyService {
  static String get _systemSshDir {
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? 'C:/Users/user'}\\.ssh';
    }
    return '${Platform.environment['HOME'] ?? '/home/user'}/.ssh';
  }

  static Future<String> get _appSshDir async {
    final dir = await getApplicationSupportDirectory();
    final p = '${dir.path}/ssh';
    Directory(p).createSync(recursive: true);
    return p;
  }

  // Returns the platform-appropriate default path for storing vaults.
  static Future<String> defaultVaultPath() async {
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final path = ext.path;
          final idx = path.indexOf('/Android/data/');
          if (idx > 0) return '${path.substring(0, idx)}/OpenVault';
        }
      } catch (_) {}
      return '/storage/emulated/0/OpenVault';
    }
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? 'C:/Users/user'}\\Documents\\OpenVault';
    }
    return '${Platform.environment['HOME'] ?? '/home/user'}/OpenVault';
  }

  // Returns the starting directory for the folder picker.
  static Future<String> browseRoot() async {
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final path = ext.path;
          final idx = path.indexOf('/Android/data/');
          if (idx > 0) return path.substring(0, idx);
        }
      } catch (_) {}
      return '/storage/emulated/0';
    }
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:/Users/user';
    }
    return Platform.environment['HOME'] ?? '/home/user';
  }

  // Finds an existing SSH key. Checks system keys on Linux/Windows, then app-managed key.
  static Future<SshKeyInfo?> findKey() async {
    if (!Platform.isAndroid) {
      final dir = _systemSshDir;
      for (final name in ['id_ed25519', 'id_rsa', 'id_ecdsa', 'id_openvault']) {
        final priv = File('$dir${Platform.pathSeparator}$name');
        final pub = File('$dir${Platform.pathSeparator}$name.pub');
        if (priv.existsSync() && pub.existsSync()) {
          return SshKeyInfo(
            privateKeyPath: priv.path,
            publicKey: pub.readAsStringSync().trim(),
            isSystemKey: name != 'id_openvault',
          );
        }
      }
    }
    // App-managed key (used on Android or when no system key exists)
    final appSsh = await _appSshDir;
    final priv = File('$appSsh/id_openvault');
    final pub = File('$appSsh/id_openvault.pub');
    if (priv.existsSync() && pub.existsSync()) {
      return SshKeyInfo(
        privateKeyPath: priv.path,
        publicKey: pub.readAsStringSync().trim(),
        isSystemKey: false,
      );
    }
    return null;
  }

  // Generates a new SSH key. Uses ssh-keygen on Linux/Windows, pure Dart on Android.
  static Future<SshKeyInfo> generateKey() async {
    if (!Platform.isAndroid) {
      try {
        return await _generateViaSshKeygen();
      } catch (_) {}
    }
    return await _generateViaDart();
  }

  static Future<SshKeyInfo> _generateViaSshKeygen() async {
    final sep = Platform.pathSeparator;
    final dir = _systemSshDir;
    Directory(dir).createSync(recursive: true);
    final path = '$dir${sep}id_openvault';
    final result = await Process.run(
      'ssh-keygen',
      ['-t', 'ed25519', '-f', path, '-N', '', '-C', 'openvault', '-q'],
    );
    if (result.exitCode != 0) throw Exception(result.stderr.toString());
    final pub = File('$path.pub').readAsStringSync().trim();
    return SshKeyInfo(privateKeyPath: path, publicKey: pub, isSystemKey: false);
  }

  // Pure-Dart Ed25519 key generation + OpenSSH serialization (for Android).
  static Future<SshKeyInfo> _generateViaDart() async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final data = await keyPair.extract();
    final seed = Uint8List.fromList(data.bytes);
    final pubBytes = Uint8List.fromList(data.publicKey.bytes);

    // OpenSSH private key = seed || public (64 bytes)
    final privBytes = Uint8List(64)
      ..setAll(0, seed)
      ..setAll(32, pubBytes);

    const comment = 'openvault';
    final privPem = _buildOpenSshPrivKey(pubBytes, privBytes, comment);
    final pubStr = 'ssh-ed25519 ${_buildSshPublicBlob(pubBytes)} $comment';

    final appSsh = await _appSshDir;
    final keyPath = '$appSsh/id_openvault';
    File(keyPath).writeAsStringSync(privPem);
    File('$keyPath.pub').writeAsStringSync('$pubStr\n');
    if (!Platform.isWindows) await Process.run('chmod', ['600', keyPath]);

    return SshKeyInfo(privateKeyPath: keyPath, publicKey: pubStr, isSystemKey: false);
  }

  // Serialises an Ed25519 key pair as an unencrypted OpenSSH private key PEM.
  static String _buildOpenSshPrivKey(Uint8List pubBytes, Uint8List privBytes, String comment) {
    final typeTag = utf8.encode('ssh-ed25519');
    final commentBytes = utf8.encode(comment);

    // Public key blob: uint32(type) + type + uint32(pub) + pub
    final pubBlob = _concat([_u32(typeTag.length), typeTag, _u32(pubBytes.length), pubBytes]);

    // Random check int (same twice — used to detect decryption errors)
    final checkInt = Random.secure().nextInt(0xFFFFFFFF);
    final check = _u32(checkInt);

    // Private key section body (before padding)
    final body = _concat([
      check, check, // checkint x2
      _u32(typeTag.length), typeTag,
      _u32(pubBytes.length), pubBytes,
      _u32(privBytes.length), privBytes,
      _u32(commentBytes.length), commentBytes,
    ]);

    // Pad to multiple of 8 (block size for "none" cipher)
    final padded = BytesBuilder()..add(body);
    for (int i = 1; padded.length % 8 != 0; i++) padded.addByte(i);
    final privSect = padded.toBytes();

    // Full binary structure
    final raw = _concat([
      [...utf8.encode('openssh-key-v1'), 0], // magic + NUL
      _u32(4), utf8.encode('none'), // ciphername
      _u32(4), utf8.encode('none'), // kdfname
      _u32(0), // kdfoptions (empty)
      _u32(1), // number of keys
      _u32(pubBlob.length), pubBlob,
      _u32(privSect.length), privSect,
    ]);

    // Base64-encode in 70-char lines
    final b64 = base64.encode(raw);
    final sb = StringBuffer('-----BEGIN OPENSSH PRIVATE KEY-----\n');
    for (int i = 0; i < b64.length; i += 70) {
      sb.writeln(b64.substring(i, (i + 70).clamp(0, b64.length)));
    }
    sb.write('-----END OPENSSH PRIVATE KEY-----\n');
    return sb.toString();
  }

  // Builds the base64 blob for the public key file (ssh-ed25519 <blob> comment).
  static String _buildSshPublicBlob(Uint8List pubBytes) {
    final typeTag = utf8.encode('ssh-ed25519');
    final blob = _concat([_u32(typeTag.length), typeTag, _u32(pubBytes.length), pubBytes]);
    return base64.encode(blob);
  }

  static Uint8List _u32(int v) => Uint8List(4)
    ..[0] = (v >> 24) & 0xFF
    ..[1] = (v >> 16) & 0xFF
    ..[2] = (v >> 8) & 0xFF
    ..[3] = v & 0xFF;

  static Uint8List _concat(List<List<int>> parts) {
    final b = BytesBuilder();
    for (final p in parts) b.add(p);
    return b.toBytes();
  }
}
