import 'task_parser.dart';
import 'vault_task.dart';

/// In-memory index of all tasks in the vault.
///
/// A2 keeps this decoupled from file I/O: callers hand it file contents
/// (`path → text`) via [rebuildFromFiles]. The wiring to the actual vault
/// (backend on web, LocalVaultService on native) lands in A3/A4.
class TaskIndex {
  TaskIndex({TaskParser? parser}) : _parser = parser ?? TaskParser();

  TaskParser _parser;
  final List<VaultTask> _tasks = [];

  List<VaultTask> get tasks => List.unmodifiable(_tasks);

  /// Swaps the parser (e.g. when the global-filter setting changes) and clears
  /// the index — caller should rebuild afterwards.
  set parser(TaskParser value) {
    _parser = value;
    _tasks.clear();
  }

  /// Parses a single file's [content] into tasks (used for incremental updates).
  List<VaultTask> parseContent(String filePath, String content) {
    final out = <VaultTask>[];
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final task = _parser.parseLine(filePath, i, lines[i]);
      if (task != null) out.add(task);
    }
    return out;
  }

  /// Rebuilds the whole index from a map of `path → file content`.
  void rebuildFromFiles(Map<String, String> files) {
    _tasks.clear();
    files.forEach((path, content) {
      _tasks.addAll(parseContent(path, content));
    });
  }

  /// Replaces all tasks for a single file (incremental update on save).
  void updateFile(String filePath, String content) {
    _tasks.removeWhere((t) => t.filePath == filePath);
    _tasks.addAll(parseContent(filePath, content));
  }

  // ── Query helpers (used by the panel + query blocks in A3/A4) ──────────────

  List<VaultTask> get open => _tasks.where((t) => !t.done).toList();

  List<VaultTask> overdue(DateTime now) =>
      _tasks.where((t) => t.isOverdue(now)).toList();

  List<VaultTask> dueOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _tasks.where((t) {
      final due = t.due;
      return due != null && due.year == d.year && due.month == d.month && due.day == d.day;
    }).toList();
  }

  List<VaultTask> dueBefore(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _tasks.where((t) => t.due != null && t.due!.isBefore(d)).toList();
  }
}
