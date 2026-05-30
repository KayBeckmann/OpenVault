import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../models/user.dart';
import '../models/vault.dart';

const _uuid = Uuid();

class GitService {
  final String _vaultRoot;

  GitService() : _vaultRoot = Platform.environment['VAULT_ROOT'] ?? '/tmp/openvault_vaults';

  List<Vault> listVaults(User user) {
    final rows = db.select(
      'SELECT * FROM vaults WHERE user_id = ? ORDER BY created_at DESC',
      [user.id],
    );
    return rows.map(Vault.fromRow).toList();
  }

  Future<Vault> cloneVault(User user, String name, String remoteUrl, {String? sshKeyId}) async {
    if (name.trim().isEmpty) throw GitException('name is required', 400);
    if (remoteUrl.trim().isEmpty) throw GitException('remoteUrl is required', 400);

    final id = _uuid.v4();
    final clonePath = '$_vaultRoot/${user.id}/$id';
    await Directory(clonePath).parent.create(recursive: true);

    final encKey = sshKeyId != null ? _lookupEncryptedKey(user.id, sshKeyId) : null;

    late Vault vault;
    await _withSshEnv(encKey, (env) async {
      final result = await Process.run(
        'git', ['clone', '--', remoteUrl.trim(), clonePath],
        environment: env,
      );
      if (result.exitCode != 0) {
        throw GitException('Clone failed: ${result.stderr}', 422);
      }

      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        'INSERT INTO vaults (id, user_id, name, remote_url, clone_path, ssh_key_id, last_synced_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, user.id, name.trim(), remoteUrl.trim(), clonePath, sshKeyId, now, now],
      );

      vault = Vault(
        id: id,
        userId: user.id,
        name: name.trim(),
        remoteUrl: remoteUrl.trim(),
        clonePath: clonePath,
        sshKeyId: sshKeyId,
        lastSyncedAt: now,
        createdAt: now,
      );
    });

    return vault;
  }

  Future<Map<String, dynamic>> pullVault(User user, String vaultId) async {
    final vault = _getVault(user, vaultId);
    final encKey = vault.sshKeyId != null ? _lookupEncryptedKey(user.id, vault.sshKeyId!) : null;

    late Map<String, dynamic> result;
    await _withSshEnv(encKey, (env) async {
      final r = await Process.run(
        'git', ['-C', vault.clonePath, 'pull', '--ff-only'],
        environment: env,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute('UPDATE vaults SET last_synced_at = ? WHERE id = ?', [now, vaultId]);
      if (r.exitCode != 0) throw GitException('Pull failed: ${r.stderr}', 422);
      result = {'output': (r.stdout as String).trim(), 'lastSyncedAt': now};
    });

    return result;
  }

  Future<Map<String, dynamic>> pushVault(User user, String vaultId, String commitMessage) async {
    final vault = _getVault(user, vaultId);
    final encKey = vault.sshKeyId != null ? _lookupEncryptedKey(user.id, vault.sshKeyId!) : null;

    late Map<String, dynamic> result;
    await _withSshEnv(encKey, (env) async {
      await Process.run('git', ['-C', vault.clonePath, 'add', '-A'], environment: env);

      final statusResult = await Process.run(
        'git', ['-C', vault.clonePath, 'status', '--porcelain'],
        environment: env,
      );
      if ((statusResult.stdout as String).trim().isEmpty) {
        result = {'output': 'Nothing to commit', 'committed': false};
        return;
      }

      final commitResult = await Process.run(
        'git',
        ['-C', vault.clonePath, 'commit', '-m', commitMessage.isEmpty ? 'Update from OpenVault' : commitMessage],
        environment: {
          ...env,
          'GIT_AUTHOR_NAME': 'OpenVault',
          'GIT_AUTHOR_EMAIL': 'vault@openvault.local',
          'GIT_COMMITTER_NAME': 'OpenVault',
          'GIT_COMMITTER_EMAIL': 'vault@openvault.local',
        },
      );
      if (commitResult.exitCode != 0) throw GitException('Commit failed: ${commitResult.stderr}', 422);

      final pushResult = await Process.run(
        'git', ['-C', vault.clonePath, 'push'],
        environment: env,
      );
      if (pushResult.exitCode != 0) throw GitException('Push failed: ${pushResult.stderr}', 422);

      final now = DateTime.now().toUtc().toIso8601String();
      db.execute('UPDATE vaults SET last_synced_at = ? WHERE id = ?', [now, vaultId]);
      result = {'output': (pushResult.stdout as String).trim(), 'committed': true, 'lastSyncedAt': now};
    });

    return result;
  }

  Future<Map<String, dynamic>> getDiff(User user, String vaultId) async {
    final vault = _getVault(user, vaultId);
    final result = await Process.run('git', ['-C', vault.clonePath, 'diff', '--stat', 'HEAD']);
    return {'diff': (result.stdout as String).trim()};
  }

  void deleteVault(User user, String vaultId) {
    final vault = _getVault(user, vaultId);
    db.execute('DELETE FROM vaults WHERE id = ?', [vaultId]);
    Directory(vault.clonePath).deleteSync(recursive: true);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  Vault _getVault(User user, String vaultId) {
    final rows = db.select(
      'SELECT * FROM vaults WHERE id = ? AND user_id = ?',
      [vaultId, user.id],
    );
    if (rows.isEmpty) throw GitException('Vault not found', 404);
    return Vault.fromRow(rows.first);
  }

  String? _lookupEncryptedKey(String userId, String sshKeyId) {
    final rows = db.select(
      'SELECT private_key_enc FROM ssh_keys WHERE id = ? AND user_id = ?',
      [sshKeyId, userId],
    );
    return rows.isEmpty ? null : rows.first['private_key_enc'] as String?;
  }

  // Sets up GIT_SSH_COMMAND with a temp key file, runs [action], then cleans up.
  Future<void> _withSshEnv(String? encryptedKeyBlob, Future<void> Function(Map<String, String>) action) async {
    final baseEnv = {
      'GIT_TERMINAL_PROMPT': '0',
      'HOME': Platform.environment['HOME'] ?? '/root',
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
    };

    if (encryptedKeyBlob == null) {
      await action(baseEnv);
      return;
    }

    final tmpDir = await Directory.systemTemp.createTemp('openvault_ssh_');
    try {
      final keyFile = File('${tmpDir.path}/id_rsa');
      final knownHostsFile = File('${tmpDir.path}/known_hosts');

      // Decrypt and write private key — trailing newline required by OpenSSH
      final pem = _decryptKey(encryptedKeyBlob);
      final pemContent = pem.endsWith('\n') ? pem : '$pem\n';
      await keyFile.writeAsString(pemContent);
      final chmodResult = await Process.run('chmod', ['600', keyFile.path]);
      if (chmodResult.exitCode != 0) {
        throw GitException('Failed to set key file permissions', 500);
      }

      // Pre-populate GitHub/GitLab host keys to avoid interactive prompt
      await knownHostsFile.writeAsString(_knownHosts);

      final env = {
        ...baseEnv,
        'GIT_SSH_COMMAND':
            'ssh -i ${keyFile.path} -o UserKnownHostsFile=${knownHostsFile.path} -o StrictHostKeyChecking=accept-new -o BatchMode=yes',
      };

      try {
        await action(env);
      } on GitException catch (e) {
        // Make libcrypto / key-format errors actionable
        final msg = e.message.toLowerCase();
        if (msg.contains('libcrypto') || msg.contains('invalid format') || msg.contains('load key')) {
          throw GitException(
            'SSH key format error — please delete this key in OpenVault, generate a new one, and add the new public key to GitHub/GitLab.',
            422,
          );
        }
        rethrow;
      }
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }

  String _decryptKey(String blob) {
    final bytes = base64.decode(blob);
    final nonce = bytes.sublist(0, 12);
    final ciphertext = bytes.sublist(12);

    final rawKey = Platform.environment['ENCRYPTION_KEY'] ?? 'dev-key-32-bytes-pad-to-length!!';
    final rawEnv = utf8.encode(rawKey);
    final keyBytes = Uint8List(32);
    for (var i = 0; i < 32; i++) keyBytes[i] = i < rawEnv.length ? rawEnv[i] : 0x21;

    final params = AEADParameters(KeyParameter(keyBytes), 128, nonce, Uint8List(0));
    final cipher = GCMBlockCipher(AESEngine())..init(false, params);
    return utf8.decode(cipher.process(ciphertext));
  }

  // GitHub and GitLab host keys (avoids interactive first-connect prompt)
  static const _knownHosts = '''
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C53LowrzZy8n49D8HEYrzIqXiG/at5D5iKUjpJa0eb3L68Gg/nF/RqIEPiJRwrTdgAypHUSdFP9VqRG/WNhwuD6arXkh3mErFCNQQgJSiRjNNLrFIiCgJRvuqml7OD7el7LDmain5VaFW0BDMLS/F4stcKBsRgbgVFYNaAcBGt+5J5r1GDrA7cVlJA0Tq+p6CgvFMoR2BPMBfOIKCBiN8ZG7UPSqYJHVSMnLPsHfQ8=
gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGgoYih0xgCiITNggg0FxUZdWfMM3Bra2FZvkInkPcRD8sVGrSRuMqCDSWECxNBMlpK4=
gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
''';
}

class GitException implements Exception {
  final String message;
  final int statusCode;
  const GitException(this.message, this.statusCode);
}
