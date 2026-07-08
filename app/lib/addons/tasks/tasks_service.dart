import 'package:flutter/foundation.dart';
import 'task_index.dart';
import 'task_parser.dart';
import 'vault_file_access.dart';
import 'vault_task.dart';

/// Builds and holds the vault-wide task index for the Tasks add-on.
///
/// Reads only files that contain the global filter tag (via search), so it does
/// not scan the whole vault. Read-only for now — write-back lands in A3b-2b.
class TasksService extends ChangeNotifier {
  TasksService(this._access, {String globalFilter = '#task'})
      : _globalFilter = globalFilter,
        _index = TaskIndex(parser: TaskParser(globalFilter: globalFilter));

  final VaultFileAccess _access;
  final String _globalFilter;
  final TaskIndex _index;

  bool _loading = false;
  bool get loading => _loading;

  List<VaultTask> get tasks => _index.tasks;

  /// Rebuilds the index from the vault. Safe to call again to refresh.
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final paths = await _access.pathsContaining(_globalFilter);
      final files = <String, String>{};
      for (final path in paths) {
        try {
          files[path] = await _access.read(path);
        } catch (_) {
          // Skip unreadable files rather than failing the whole rebuild.
        }
      }
      _index.rebuildFromFiles(files);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
