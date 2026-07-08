import 'vault_task.dart';

/// Parses Markdown checklist lines into [VaultTask]s using the Obsidian Tasks
/// emoji syntax. Only lines carrying the [globalFilter] tag are treated as
/// tasks (mirrors the Obsidian "global filter" setting), so ordinary
/// checkboxes — e.g. in skill docs — are ignored.
class TaskParser {
  TaskParser({this.globalFilter = '#task'});

  /// Tag that a line must contain to count as a task. Empty = match all.
  final String globalFilter;

  // `- [ ] text` / `* [x] text` (leading indentation allowed).
  static final _checkbox = RegExp(r'^\s*[-*]\s+\[([ xX])\]\s+(.*)$');
  static final _dueRe = RegExp(r'📅\s*(\d{4}-\d{2}-\d{2})');
  static final _doneRe = RegExp(r'✅\s*(\d{4}-\d{2}-\d{2})');
  static final _tagRe = RegExp(r'#[\p{L}\p{N}_/\-]+', unicode: true);

  static const _priorityEmoji = {
    '🔺': TaskPriority.highest,
    '⏫': TaskPriority.high,
    '🔼': TaskPriority.medium,
    '🔽': TaskPriority.low,
    '⏬': TaskPriority.lowest,
  };

  /// Returns a [VaultTask] for [raw], or null if the line is not a (matching) task.
  VaultTask? parseLine(String filePath, int lineIndex, String raw) {
    final m = _checkbox.firstMatch(raw);
    if (m == null) return null;

    final done = m.group(1)!.toLowerCase() == 'x';
    var body = m.group(2)!.trim();

    final tags = _tagRe.allMatches(body).map((e) => e.group(0)!).toSet();
    if (globalFilter.isNotEmpty && !tags.contains(globalFilter)) return null;

    DateTime? due;
    final dueM = _dueRe.firstMatch(body);
    if (dueM != null) due = DateTime.tryParse(dueM.group(1)!);

    DateTime? doneDate;
    final doneM = _doneRe.firstMatch(body);
    if (doneM != null) doneDate = DateTime.tryParse(doneM.group(1)!);

    var priority = TaskPriority.none;
    for (final entry in _priorityEmoji.entries) {
      if (body.contains(entry.key)) {
        priority = entry.value;
        break;
      }
    }

    final description = _stripSignifiers(body);

    return VaultTask(
      filePath: filePath,
      line: lineIndex,
      done: done,
      description: description,
      tags: tags,
      due: due,
      priority: priority,
      doneDate: doneDate,
    );
  }

  /// Removes emoji signifiers (dates, priority) for a clean display string.
  /// Tags are kept — they are part of the description in Obsidian too.
  String _stripSignifiers(String body) {
    var out = body
        .replaceAll(_dueRe, '')
        .replaceAll(_doneRe, '');
    for (final emoji in _priorityEmoji.keys) {
      out = out.replaceAll(emoji, '');
    }
    // Collapse whitespace left behind by removed tokens.
    return out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}
