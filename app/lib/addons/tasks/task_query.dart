import 'vault_task.dart';

/// A group of tasks under a heading (empty label = no grouping).
class TaskGroup {
  const TaskGroup(this.label, this.tasks);
  final String label;
  final List<VaultTask> tasks;
}

enum _SortKey { priority, due, path, description }

/// Parses and executes a subset of the Obsidian Tasks query language found in
/// ```` ```tasks ```` blocks. Unknown lines are ignored (kept forward-compatible).
///
/// Supported:
///   not done | done
///   due before|after|on YYYY-MM-DD
///   no due date | has due date
///   path includes <text>
///   tag includes #tag
///   sort by priority|due|path|description   (repeatable)
///   group by priority|due|path
///   limit N
class TaskQuery {
  TaskQuery._({
    required List<bool Function(VaultTask, DateTime)> filters,
    required List<_SortKey> sortKeys,
    String? groupBy,
    int? limit,
  })  : _filters = filters,
        _sortKeys = sortKeys,
        _groupBy = groupBy,
        _limit = limit;

  final List<bool Function(VaultTask, DateTime)> _filters;
  final List<_SortKey> _sortKeys;
  final String? _groupBy;
  final int? _limit;

  /// Resolves an absolute (`YYYY-MM-DD`) or relative (`today`/`tomorrow`/
  /// `yesterday`) date token, using [now] as the anchor.
  static DateTime? _resolveDate(String token, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (token.trim().toLowerCase()) {
      case 'today':
        return today;
      case 'tomorrow':
        return today.add(const Duration(days: 1));
      case 'yesterday':
        return today.subtract(const Duration(days: 1));
    }
    return DateTime.tryParse(token.trim());
  }

  static TaskPriority? _priorityFromName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'highest':
        return TaskPriority.highest;
      case 'high':
        return TaskPriority.high;
      case 'medium':
        return TaskPriority.medium;
      case 'none':
        return TaskPriority.none;
      case 'low':
        return TaskPriority.low;
      case 'lowest':
        return TaskPriority.lowest;
    }
    return null;
  }

  factory TaskQuery.parse(String body) {
    final filters = <bool Function(VaultTask, DateTime)>[];
    final sortKeys = <_SortKey>[];
    String? groupBy;
    int? limit;

    for (var raw in body.split('\n')) {
      final line = raw.trim().toLowerCase();
      if (line.isEmpty) continue;

      if (line == 'not done') {
        filters.add((t, _) => !t.done);
      } else if (line == 'done') {
        filters.add((t, _) => t.done);
      } else if (line == 'no due date') {
        filters.add((t, _) => t.due == null);
      } else if (line == 'has due date') {
        filters.add((t, _) => t.due != null);
      } else if (line.startsWith('due before ')) {
        final tok = line.substring('due before '.length).trim();
        filters.add((t, now) {
          final d = _resolveDate(tok, now);
          return d != null && t.due != null && t.due!.isBefore(d);
        });
      } else if (line.startsWith('due after ')) {
        final tok = line.substring('due after '.length).trim();
        filters.add((t, now) {
          final d = _resolveDate(tok, now);
          return d != null && t.due != null && t.due!.isAfter(d);
        });
      } else if (line.startsWith('due on ')) {
        final tok = line.substring('due on '.length).trim();
        filters.add((t, now) {
          final d = _resolveDate(tok, now);
          return d != null &&
              t.due != null &&
              t.due!.year == d.year &&
              t.due!.month == d.month &&
              t.due!.day == d.day;
        });
      } else if (line.startsWith('priority is ')) {
        final p = _priorityFromName(line.substring('priority is '.length));
        if (p != null) filters.add((t, _) => t.priority == p);
      } else if (line.startsWith('path includes ')) {
        final needle = line.substring('path includes '.length).trim();
        filters.add((t, _) => t.filePath.toLowerCase().contains(needle));
      } else if (line.startsWith('tag includes ') || line.startsWith('tags include ')) {
        final prefix = line.startsWith('tags include ') ? 'tags include ' : 'tag includes ';
        var needle = line.substring(prefix.length).trim();
        if (needle.isNotEmpty && !needle.startsWith('#')) needle = '#$needle';
        filters.add((t, _) => t.tags.any((tag) => tag.toLowerCase() == needle));
      } else if (line.startsWith('sort by ')) {
        final key = line.substring('sort by '.length).trim();
        for (final k in key.split(',')) {
          switch (k.trim()) {
            case 'priority':
              sortKeys.add(_SortKey.priority);
              break;
            case 'due':
              sortKeys.add(_SortKey.due);
              break;
            case 'path':
              sortKeys.add(_SortKey.path);
              break;
            case 'description':
              sortKeys.add(_SortKey.description);
              break;
          }
        }
      } else if (line.startsWith('group by ')) {
        groupBy = line.substring('group by '.length).trim();
      } else if (line.startsWith('limit ')) {
        limit = int.tryParse(line.substring('limit '.length).trim());
      }
      // Unknown directives are ignored on purpose.
    }

    return TaskQuery._(
      filters: filters,
      sortKeys: sortKeys,
      groupBy: groupBy,
      limit: limit,
    );
  }

  /// Runs the query against [tasks]. [now] anchors relative date logic.
  List<TaskGroup> run(List<VaultTask> tasks, {DateTime? now}) {
    final anchor = now ?? DateTime.now();

    var result = tasks.where((t) => _filters.every((f) => f(t, anchor))).toList();

    if (_sortKeys.isNotEmpty) {
      result.sort((a, b) {
        for (final key in _sortKeys) {
          final c = _compare(key, a, b);
          if (c != 0) return c;
        }
        return 0;
      });
    }

    if (_limit != null && result.length > _limit) {
      result = result.sublist(0, _limit);
    }

    if (_groupBy == null) {
      return [TaskGroup('', result)];
    }
    return _group(result);
  }

  int _compare(_SortKey key, VaultTask a, VaultTask b) {
    switch (key) {
      case _SortKey.priority:
        return a.priority.index.compareTo(b.priority.index); // highest=0 first
      case _SortKey.due:
        if (a.due == null && b.due == null) return 0;
        if (a.due == null) return 1; // nulls last
        if (b.due == null) return -1;
        return a.due!.compareTo(b.due!);
      case _SortKey.path:
        return a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase());
      case _SortKey.description:
        return a.description.toLowerCase().compareTo(b.description.toLowerCase());
    }
  }

  List<TaskGroup> _group(List<VaultTask> tasks) {
    final map = <String, List<VaultTask>>{};
    for (final t in tasks) {
      final label = _groupLabel(t);
      map.putIfAbsent(label, () => []).add(t);
    }
    final labels = map.keys.toList()..sort();
    return [for (final l in labels) TaskGroup(l, map[l]!)];
  }

  String _groupLabel(VaultTask t) {
    switch (_groupBy) {
      case 'due':
        final d = t.due;
        return d == null
            ? 'Ohne Datum'
            : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      case 'priority':
        return t.priority.name;
      case 'path':
        return t.filePath;
      default:
        return '';
    }
  }
}
