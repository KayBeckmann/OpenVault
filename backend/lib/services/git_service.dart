import 'dart:io';
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

    final env = await _buildGitEnv(user.id, sshKeyId);
    final result = await Process.run(
      'git',
      ['clone', '--', remoteUrl.trim(), clonePath],
      environment: env,
    );

    if (result.exitCode != 0) {
      throw GitException('Clone failed: ${result.stderr}', 422);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO vaults (id, user_id, name, remote_url, clone_path, last_synced_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, user.id, name.trim(), remoteUrl.trim(), clonePath, now, now],
    );

    return Vault(
      id: id,
      userId: user.id,
      name: name.trim(),
      remoteUrl: remoteUrl.trim(),
      clonePath: clonePath,
      lastSyncedAt: now,
      createdAt: now,
    );
  }

  Future<Map<String, dynamic>> pullVault(User user, String vaultId) async {
    final vault = _getVault(user, vaultId);
    final env = await _buildGitEnv(user.id, null);

    final result = await Process.run(
      'git', ['-C', vault.clonePath, 'pull', '--ff-only'],
      environment: env,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('UPDATE vaults SET last_synced_at = ? WHERE id = ?', [now, vaultId]);

    if (result.exitCode != 0) {
      throw GitException('Pull failed: ${result.stderr}', 422);
    }

    return {
      'output': (result.stdout as String).trim(),
      'lastSyncedAt': now,
    };
  }

  Future<Map<String, dynamic>> pushVault(User user, String vaultId, String commitMessage) async {
    final vault = _getVault(user, vaultId);
    final env = await _buildGitEnv(user.id, null);

    // Stage all changes
    await Process.run('git', ['-C', vault.clonePath, 'add', '-A'], environment: env);

    // Check if there's anything to commit
    final statusResult = await Process.run(
      'git', ['-C', vault.clonePath, 'status', '--porcelain'],
      environment: env,
    );

    if ((statusResult.stdout as String).trim().isEmpty) {
      return {'output': 'Nothing to commit', 'committed': false};
    }

    // Commit
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

    if (commitResult.exitCode != 0) {
      throw GitException('Commit failed: ${commitResult.stderr}', 422);
    }

    // Push
    final pushResult = await Process.run(
      'git', ['-C', vault.clonePath, 'push'],
      environment: env,
    );

    if (pushResult.exitCode != 0) {
      throw GitException('Push failed: ${pushResult.stderr}', 422);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('UPDATE vaults SET last_synced_at = ? WHERE id = ?', [now, vaultId]);

    return {
      'output': (pushResult.stdout as String).trim(),
      'committed': true,
      'lastSyncedAt': now,
    };
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

  Vault _getVault(User user, String vaultId) {
    final rows = db.select(
      'SELECT * FROM vaults WHERE id = ? AND user_id = ?',
      [vaultId, user.id],
    );
    if (rows.isEmpty) throw GitException('Vault not found', 404);
    return Vault.fromRow(rows.first);
  }

  Future<Map<String, String>> _buildGitEnv(String userId, String? sshKeyId) async {
    // GIT_TERMINAL_PROMPT=0 prevents git from hanging waiting for input
    final env = <String, String>{
      'GIT_TERMINAL_PROMPT': '0',
      'HOME': Platform.environment['HOME'] ?? '/root',
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
    };

    if (sshKeyId != null) {
      final rows = db.select(
        'SELECT private_key_enc FROM ssh_keys WHERE id = ? AND user_id = ?',
        [sshKeyId, userId],
      );
      if (rows.isNotEmpty) {
        // Write decrypted key to temp file
        // (decryption skipped for Phase 4 — SSH keys used by placing public key at remote)
        // Full decryption added in Phase 7 (encryption at rest)
      }
    }

    return env;
  }
}

class GitException implements Exception {
  final String message;
  final int statusCode;
  const GitException(this.message, this.statusCode);
}
