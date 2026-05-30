import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'git_channel.dart';

class LocalVaultService {
  static Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/vaults.json');
  }

  static Future<List<Map<String, dynamic>>> loadVaults() async {
    try {
      final f = await _file;
      if (!f.existsSync()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> vaults) async {
    (await _file).writeAsStringSync(jsonEncode(vaults));
  }

  static Future<Map<String, dynamic>> addVault({
    required String name,
    required String localPath,
    String? remoteUrl,
  }) async {
    final vaults = await loadVaults();
    final vault = <String, dynamic>{
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'localPath': localPath,
      if (remoteUrl != null && remoteUrl.isNotEmpty) 'remoteUrl': remoteUrl,
    };
    vaults.add(vault);
    await _save(vaults);
    return vault;
  }

  static Future<void> removeVault(String id) async {
    final vaults = await loadVaults();
    vaults.removeWhere((v) => v['id'] == id);
    await _save(vaults);
  }

  static List<Map<String, dynamic>> buildTree(String basePath) =>
      _scanDir(Directory(basePath), basePath);

  static List<Map<String, dynamic>> _scanDir(Directory dir, String base) {
    final result = <Map<String, dynamic>>[];
    try {
      final entries = dir.listSync(followLinks: false)
        ..sort((a, b) {
          final aD = a is Directory, bD = b is Directory;
          if (aD != bD) return aD ? -1 : 1;
          return a.path.compareTo(b.path);
        });
      for (final e in entries) {
        final name = _base(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          result.add({
            'type': 'folder',
            'name': name,
            'path': _rel(e.path, base),
            'children': _scanDir(e, base),
          });
        } else if (e is File && (name.endsWith('.md') || name.endsWith('.txt'))) {
          result.add({'type': 'file', 'name': name, 'path': _rel(e.path, base)});
        }
      }
    } catch (_) {}
    return result;
  }

  static String readFile(String base, String rel) =>
      File('$base/$rel').readAsStringSync();

  static void writeFile(String base, String rel, String content) {
    final f = File('$base/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  static void deleteFile(String base, String rel) =>
      File('$base/$rel').deleteSync();

  static void createFolder(String base, String rel) =>
      Directory('$base/$rel').createSync(recursive: true);

  static List<Map<String, dynamic>> searchFiles(String base, String query) {
    final results = <Map<String, dynamic>>[];
    _searchDir(Directory(base), base, query.toLowerCase(), results);
    return results;
  }

  static void _searchDir(
    Directory dir,
    String base,
    String query,
    List<Map<String, dynamic>> out,
  ) {
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = _base(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          _searchDir(e, base, query, out);
        } else if (e is File && (name.endsWith('.md') || name.endsWith('.txt'))) {
          try {
            final content = e.readAsStringSync();
            if (name.toLowerCase().contains(query) || content.toLowerCase().contains(query)) {
              final preview = content
                  .split('\n')
                  .firstWhere((l) => l.toLowerCase().contains(query), orElse: () => '')
                  .trim();
              out.add({'path': _rel(e.path, base), 'preview': preview});
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static List<String> collectFilePaths(String base) {
    final result = <String>[];
    _collectPaths(Directory(base), base, result);
    return result;
  }

  static void _collectPaths(Directory dir, String base, List<String> out) {
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = _base(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          _collectPaths(e, base, out);
        } else if (e is File && (name.endsWith('.md') || name.endsWith('.txt'))) {
          out.add(_rel(e.path, base));
        }
      }
    } catch (_) {}
  }

  static Future<void> setVaultProperty(String id, String key, dynamic value) async {
    final vaults = await loadVaults();
    final idx = vaults.indexWhere((v) => v['id'] == id);
    if (idx < 0) return;
    vaults[idx][key] = value;
    await _save(vaults);
  }

  // ── Git operations ──────────────────────────────────────────────────────────

  static Map<String, String> _gitEnv({String? sshKeyPath}) => {
    ...Platform.environment,
    'GIT_TERMINAL_PROMPT': '0',
    if (sshKeyPath != null)
      'GIT_SSH_COMMAND':
          'ssh -i "$sshKeyPath" -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes',
  };

  static Future<bool> _gitAvailable() async {
    try {
      final r = await Process.run('git', ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<({bool success, String output})> pullRepo(
    String repoPath, {
    String? sshKeyPath,
  }) async {
    if (Platform.isAndroid) {
      return GitChannel.pull(repoPath, sshKeyPath: sshKeyPath);
    }
    final r = await Process.run(
      'git', ['-C', repoPath, 'pull'],
      environment: _gitEnv(sshKeyPath: sshKeyPath),
    );
    return (success: r.exitCode == 0, output: '${r.stdout}${r.stderr}'.trim());
  }

  static Future<({bool success, String output})> commitAndPushRepo(
    String repoPath,
    String message, {
    String? sshKeyPath,
  }) async {
    if (Platform.isAndroid) {
      return GitChannel.commitAndPush(repoPath, message, sshKeyPath: sshKeyPath);
    }
    final env = _gitEnv(sshKeyPath: sshKeyPath);
    // Stage all changes
    var r = await Process.run('git', ['-C', repoPath, 'add', '-A'], environment: env);
    if (r.exitCode != 0) return (success: false, output: '${r.stderr}'.trim());
    // Commit (ignore "nothing to commit" — still try push)
    r = await Process.run('git', ['-C', repoPath, 'commit', '-m', message], environment: env);
    final commitOut = '${r.stdout}${r.stderr}'.trim();
    if (r.exitCode != 0 && !commitOut.toLowerCase().contains('nothing to commit')) {
      return (success: false, output: commitOut);
    }
    // Push
    r = await Process.run('git', ['-C', repoPath, 'push'], environment: env);
    return (success: r.exitCode == 0, output: '${r.stdout}${r.stderr}'.trim());
  }

  static Future<({bool success, String output})> cloneRepo(
    String url,
    String destPath, {
    String? sshKeyPath,
  }) async {
    if (Platform.isAndroid) {
      return GitChannel.clone(url, destPath, sshKeyPath: sshKeyPath);
    }
    final env = {
      ...Platform.environment,
      'GIT_TERMINAL_PROMPT': '0',
      if (sshKeyPath != null)
        'GIT_SSH_COMMAND':
            'ssh -i "$sshKeyPath" -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes',
    };
    final result = await Process.run('git', ['clone', url, destPath], environment: env);
    final out = '${result.stdout}${result.stderr}'.trim();
    return (success: result.exitCode == 0, output: out);
  }

  static String _base(String p) {
    final parts = p.replaceAll('\\', '/').split('/');
    return parts.lastWhere((s) => s.isNotEmpty, orElse: () => '');
  }

  static String _rel(String p, String base) {
    final np = p.replaceAll('\\', '/');
    final nb = base.replaceAll('\\', '/').trimRight();
    if (np.startsWith(nb)) {
      var rel = np.substring(nb.length);
      while (rel.startsWith('/')) rel = rel.substring(1);
      return rel;
    }
    return p;
  }
}
