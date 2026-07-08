/// Priority levels matching the Obsidian Tasks plugin emoji signifiers.
/// 🔺 highest · ⏫ high · 🔼 medium · (none) · 🔽 low · ⏬ lowest
enum TaskPriority { highest, high, medium, none, low, lowest }

/// A single task parsed from a Markdown checklist line.
///
/// Syntax is intentionally identical to the Obsidian Tasks plugin so the same
/// vault interoperates in both tools. See `10_Projects/OpenVault/Add-Ons.md`.
class VaultTask {
  const VaultTask({
    required this.filePath,
    required this.line,
    required this.done,
    required this.description,
    this.tags = const {},
    this.due,
    this.priority = TaskPriority.none,
    this.doneDate,
  });

  /// Vault-relative path of the file this task lives in.
  final String filePath;

  /// Zero-based line index within the file (for write-back in A3).
  final int line;

  final bool done;

  /// Human-readable text without emoji signifiers.
  final String description;

  /// All `#tags` found on the line (includes the global filter tag).
  final Set<String> tags;

  /// Due date (📅), if any.
  final DateTime? due;

  final TaskPriority priority;

  /// Completion date (✅), if any.
  final DateTime? doneDate;

  bool get hasDue => due != null;

  /// Overdue relative to [now] (date-only comparison).
  bool isOverdue(DateTime now) {
    final d = due;
    if (d == null || done) return false;
    final today = DateTime(now.year, now.month, now.day);
    return d.isBefore(today);
  }

  @override
  String toString() =>
      'VaultTask($filePath:$line, done=$done, due=$due, prio=$priority, "$description")';
}
