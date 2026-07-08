import 'package:flutter_test/flutter_test.dart';
import 'package:app/addons/tasks/task_query.dart';
import 'package:app/addons/tasks/task_writer.dart';
import 'package:app/addons/tasks/vault_task.dart';

VaultTask _t(
  String path,
  int line, {
  bool done = false,
  DateTime? due,
  TaskPriority prio = TaskPriority.none,
  Set<String> tags = const {},
  String desc = 'x',
}) =>
    VaultTask(
      filePath: path,
      line: line,
      done: done,
      description: desc,
      tags: tags,
      due: due,
      priority: prio,
    );

void main() {
  final tasks = [
    _t('plan.md', 1, due: DateTime(2026, 7, 13), prio: TaskPriority.high, tags: {'#task'}, desc: 'A'),
    _t('plan.md', 2, done: true, tags: {'#task'}, desc: 'B'),
    _t('notes.md', 5, due: DateTime(2026, 7, 20), prio: TaskPriority.medium, tags: {'#task'}, desc: 'C'),
    _t('notes.md', 8, tags: {'#task'}, desc: 'D'),
  ];

  group('TaskQuery — filters', () {
    test('not done', () {
      final r = TaskQuery.parse('not done').run(tasks);
      expect(r.single.tasks.length, 3);
    });

    test('due before', () {
      final r = TaskQuery.parse('due before 2026-07-20').run(tasks);
      expect(r.single.tasks.map((t) => t.description), ['A']);
    });

    test('combined: not done + has due date', () {
      final r = TaskQuery.parse('not done\nhas due date').run(tasks);
      expect(r.single.tasks.map((t) => t.description).toSet(), {'A', 'C'});
    });

    test('path includes', () {
      final r = TaskQuery.parse('path includes notes').run(tasks);
      expect(r.single.tasks.length, 2);
    });

    test('unknown directive is ignored', () {
      final r = TaskQuery.parse('not done\nfoobar baz').run(tasks);
      expect(r.single.tasks.length, 3);
    });
  });

  group('TaskQuery — sort / limit / group', () {
    test('sort by priority (highest first)', () {
      final r = TaskQuery.parse('has due date\nsort by priority').run(tasks);
      expect(r.single.tasks.map((t) => t.description), ['A', 'C']); // high before medium
    });

    test('sort by due, nulls last', () {
      final r = TaskQuery.parse('not done\nsort by due').run(tasks);
      expect(r.single.tasks.map((t) => t.description), ['A', 'C', 'D']);
    });

    test('limit', () {
      final r = TaskQuery.parse('not done\nsort by due\nlimit 1').run(tasks);
      expect(r.single.tasks.map((t) => t.description), ['A']);
    });

    test('group by due', () {
      final r = TaskQuery.parse('not done\ngroup by due').run(tasks);
      final labels = r.map((g) => g.label).toList();
      expect(labels, containsAll(['2026-07-13', '2026-07-20', 'Ohne Datum']));
    });
  });

  group('TaskWriter', () {
    test('complete adds ✅ done date, preserves signifiers', () {
      const c = '- [ ] #task A ⏫ 📅 2026-07-13';
      final out = TaskWriter.setDone(c, 0, done: true, date: DateTime(2026, 7, 9));
      expect(out, '- [x] #task A ⏫ 📅 2026-07-13 ✅ 2026-07-09');
    });

    test('reopen removes ✅ done date', () {
      const c = '- [x] #task A ✅ 2026-07-09';
      final out = TaskWriter.setDone(c, 0, done: false);
      expect(out, '- [ ] #task A');
    });

    test('only the target line changes', () {
      const c = 'intro\n- [ ] #task A\n- [ ] #task B';
      final out = TaskWriter.setDone(c, 2, done: true, addDoneDate: false);
      expect(out, 'intro\n- [ ] #task A\n- [x] #task B');
    });

    test('non-checkbox line is untouched', () {
      const c = 'just text';
      expect(TaskWriter.setDone(c, 0, done: true), c);
    });
  });
}
