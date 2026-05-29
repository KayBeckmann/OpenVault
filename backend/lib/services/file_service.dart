import 'dart:io';
import 'package:path/path.dart' as p;
import '../db/database.dart';
import '../models/user.dart';

class FileService {
  Map<String, dynamic> getTree(User user, String vaultId) {
    final clonePath = _getClonePath(user, vaultId);
    return _buildTree(Directory(clonePath), clonePath);
  }

  String readFile(User user, String vaultId, String relativePath) {
    _validatePath(relativePath);
    final clonePath = _getClonePath(user, vaultId);
    final file = File(p.join(clonePath, relativePath));
    if (!file.existsSync()) throw FileException('File not found', 404);
    if (!file.path.startsWith(clonePath)) throw FileException('Forbidden', 403);
    return file.readAsStringSync();
  }

  void writeFile(User user, String vaultId, String relativePath, String content) {
    _validatePath(relativePath);
    final clonePath = _getClonePath(user, vaultId);
    final file = File(p.join(clonePath, relativePath));
    if (!file.path.startsWith(clonePath)) throw FileException('Forbidden', 403);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void deleteFile(User user, String vaultId, String relativePath) {
    _validatePath(relativePath);
    final clonePath = _getClonePath(user, vaultId);
    final target = File(p.join(clonePath, relativePath));
    if (!target.path.startsWith(clonePath)) throw FileException('Forbidden', 403);
    if (!target.existsSync()) throw FileException('File not found', 404);
    target.deleteSync();
  }

  void createFolder(User user, String vaultId, String relativePath) {
    _validatePath(relativePath);
    final clonePath = _getClonePath(user, vaultId);
    final dir = Directory(p.join(clonePath, relativePath));
    if (!dir.path.startsWith(clonePath)) throw FileException('Forbidden', 403);
    dir.createSync(recursive: true);
  }

  List<Map<String, dynamic>> searchFiles(User user, String vaultId, String query) {
    if (query.trim().isEmpty) return [];
    final clonePath = _getClonePath(user, vaultId);
    final results = <Map<String, dynamic>>[];
    _walkMd(Directory(clonePath), clonePath, (file, rel) {
      final content = file.readAsStringSync();
      if (content.toLowerCase().contains(query.toLowerCase())) {
        results.add({'path': rel, 'preview': _extract(content, query)});
      }
    });
    return results;
  }

  Map<String, dynamic> getTags(User user, String vaultId) {
    final clonePath = _getClonePath(user, vaultId);
    final tagMap = <String, List<String>>{};

    _walkMd(Directory(clonePath), clonePath, (file, rel) {
      final content = file.readAsStringSync();
      final tags = _extractTags(content);
      for (final tag in tags) {
        tagMap.putIfAbsent(tag, () => []).add(rel);
      }
    });

    return {
      'tags': tagMap.entries
          .map((e) => {'tag': e.key, 'count': e.value.length, 'files': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int)),
    };
  }

  List<Map<String, dynamic>> filterByTags(User user, String vaultId, List<String> tags, String operator) {
    if (tags.isEmpty) return [];
    final clonePath = _getClonePath(user, vaultId);
    final results = <Map<String, dynamic>>[];

    _walkMd(Directory(clonePath), clonePath, (file, rel) {
      final fileTags = _extractTags(file.readAsStringSync());
      final matches = operator == 'AND'
          ? tags.every(fileTags.contains)
          : tags.any(fileTags.contains);
      if (matches) results.add({'path': rel, 'tags': fileTags});
    });

    return results;
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _getClonePath(User user, String vaultId) {
    final rows = db.select(
      'SELECT clone_path FROM vaults WHERE id = ? AND user_id = ?',
      [vaultId, user.id],
    );
    if (rows.isEmpty) throw FileException('Vault not found', 404);
    return rows.first['clone_path'] as String;
  }

  void _validatePath(String path) {
    if (path.contains('..') || path.startsWith('/')) {
      throw FileException('Invalid path', 400);
    }
  }

  Map<String, dynamic> _buildTree(Directory dir, String rootPath) {
    final entries = <Map<String, dynamic>>[];
    final items = dir.listSync()..sort((a, b) {
      final aIsDir = a is Directory ? 0 : 1;
      final bIsDir = b is Directory ? 0 : 1;
      if (aIsDir != bIsDir) return aIsDir - bIsDir;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });

    for (final item in items) {
      final name = p.basename(item.path);
      if (name.startsWith('.')) continue; // skip hidden files/dirs
      final rel = p.relative(item.path, from: rootPath);

      if (item is Directory) {
        entries.add({'type': 'folder', 'name': name, 'path': rel, 'children': _buildTree(item, rootPath)['children']});
      } else if (item is File && (name.endsWith('.md') || name.endsWith('.txt'))) {
        entries.add({'type': 'file', 'name': name, 'path': rel});
      }
    }

    return {'children': entries};
  }

  void _walkMd(Directory dir, String rootPath, void Function(File, String) callback) {
    for (final item in dir.listSync(recursive: true)) {
      if (item is File && item.path.endsWith('.md')) {
        final rel = p.relative(item.path, from: rootPath);
        callback(item, rel);
      }
    }
  }

  List<String> _extractTags(String content) {
    final tags = <String>{};
    // YAML frontmatter tags
    final fmMatch = RegExp(r'^---\n(.*?)\n---', dotAll: true).firstMatch(content);
    if (fmMatch != null) {
      final tagLine = RegExp(r'tags:\s*\[([^\]]+)\]').firstMatch(fmMatch.group(1)!);
      if (tagLine != null) {
        tags.addAll(tagLine.group(1)!.split(',').map((t) => t.trim().replaceAll('"', '').replaceAll("'", '')));
      }
      // tags: \n  - tag1 format
      final tagList = RegExp(r'tags:\s*\n((?:\s+-\s+\S+\n?)*)').firstMatch(fmMatch.group(1)!);
      if (tagList != null) {
        final matches = RegExp(r'-\s+(\S+)').allMatches(tagList.group(1)!);
        tags.addAll(matches.map((m) => m.group(1)!));
      }
    }
    // Inline #tags
    final inlineTags = RegExp(r'(?<!\w)#([A-Za-z][A-Za-z0-9_/-]*)').allMatches(content);
    tags.addAll(inlineTags.map((m) => m.group(1)!));
    return tags.where((t) => t.isNotEmpty).toList();
  }

  String _extract(String content, String query) {
    final idx = content.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) return '';
    final start = (idx - 40).clamp(0, content.length);
    final end = (idx + query.length + 40).clamp(0, content.length);
    return '…${content.substring(start, end)}…';
  }
}

class FileException implements Exception {
  final String message;
  final int statusCode;
  const FileException(this.message, this.statusCode);
}
