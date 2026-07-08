import 'package:flutter_test/flutter_test.dart';
import 'package:app/addons/tasks/task_parser.dart';
import 'package:app/addons/tasks/task_index.dart';
import 'package:app/addons/tasks/vault_task.dart';

void main() {
  final parser = TaskParser(); // default global filter '#task'

  group('TaskParser — global filter', () {
    test('line without #task is ignored', () {
      expect(parser.parseLine('f.md', 0, '- [ ] just a checkbox'), isNull);
    });

    test('non-checkbox line is ignored', () {
      expect(parser.parseLine('f.md', 0, 'plain text #task'), isNull);
    });

    test('#taskfoo does not satisfy the #task filter', () {
      expect(parser.parseLine('f.md', 0, '- [ ] nope #taskfoo'), isNull);
    });

    test('empty global filter matches every checkbox', () {
      final t = TaskParser(globalFilter: '').parseLine('f.md', 0, '- [ ] anything');
      expect(t, isNotNull);
    });
  });

  group('TaskParser — signifiers (Obsidian syntax)', () {
    test('parses the vacation-plan format', () {
      final t = parser.parseLine(
        'plan.md',
        4,
        '- [ ] #task 🥇 Mailcow: `/boot` bereinigen (< 60 %) ⏫ 📅 2026-07-13',
      )!;
      expect(t.done, isFalse);
      expect(t.line, 4);
      expect(t.priority, TaskPriority.high);
      expect(t.due, DateTime(2026, 7, 13));
      expect(t.tags, contains('#task'));
      // emoji signifiers stripped from description, text kept
      expect(t.description, contains('Mailcow'));
      expect(t.description, isNot(contains('📅')));
      expect(t.description, isNot(contains('⏫')));
    });

    test('done task with completion date', () {
      final t = parser.parseLine('f.md', 0, '- [x] #task erledigt ✅ 2026-07-01')!;
      expect(t.done, isTrue);
      expect(t.doneDate, DateTime(2026, 7, 1));
    });

    test('no due / no priority', () {
      final t = parser.parseLine('f.md', 0, '- [ ] #task simpel')!;
      expect(t.due, isNull);
      expect(t.priority, TaskPriority.none);
      expect(t.description, contains('simpel'));
    });

    test('all priority levels', () {
      expect(parser.parseLine('f', 0, '- [ ] #task a 🔺')!.priority, TaskPriority.highest);
      expect(parser.parseLine('f', 0, '- [ ] #task a ⏫')!.priority, TaskPriority.high);
      expect(parser.parseLine('f', 0, '- [ ] #task a 🔼')!.priority, TaskPriority.medium);
      expect(parser.parseLine('f', 0, '- [ ] #task a 🔽')!.priority, TaskPriority.low);
      expect(parser.parseLine('f', 0, '- [ ] #task a ⏬')!.priority, TaskPriority.lowest);
    });

    test('asterisk bullet and indentation', () {
      final t = parser.parseLine('f.md', 0, '    * [ ] #task eingerückt 📅 2026-01-05')!;
      expect(t.due, DateTime(2026, 1, 5));
      expect(t.description, contains('eingerückt'));
    });
  });

  group('TaskIndex', () {
    const content = '''
# Notiz
- [ ] #task offen A 📅 2026-07-13
- [ ] kein task
- [x] #task erledigt ✅ 2026-07-01
- [ ] #task offen B ⏫ 📅 2026-07-20
''';

    test('parseContent picks only #task lines with correct line numbers', () {
      final idx = TaskIndex();
      final tasks = idx.parseContent('n.md', content);
      expect(tasks.length, 3);
      expect(tasks.first.line, 1); // 0-based; line 0 is the heading
    });

    test('query helpers', () {
      final idx = TaskIndex();
      idx.rebuildFromFiles({'n.md': content});
      expect(idx.open.length, 2); // two not-done
      expect(idx.overdue(DateTime(2026, 7, 15)).length, 1); // only 2026-07-13
      expect(idx.dueOn(DateTime(2026, 7, 20)).length, 1);
      expect(idx.dueBefore(DateTime(2026, 7, 20)).length, 1); // exklusiv: der 20. selbst zählt nicht
      expect(idx.dueBefore(DateTime(2026, 7, 21)).length, 2); // 13. + 20.
    });

    test('updateFile replaces tasks for that file only', () {
      final idx = TaskIndex();
      idx.rebuildFromFiles({'a.md': content, 'b.md': '- [ ] #task nur B'});
      expect(idx.tasks.length, 4);
      idx.updateFile('a.md', '- [ ] #task neu A');
      expect(idx.tasks.length, 2); // 1 from a.md (new) + 1 from b.md
    });
  });
}
