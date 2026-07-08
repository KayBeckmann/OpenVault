import 'package:flutter_test/flutter_test.dart';
import 'package:app/addons/tasks/tasks_service.dart';
import 'package:app/addons/tasks/vault_file_access.dart';

class _FakeAccess implements VaultFileAccess {
  _FakeAccess(this.files);
  final Map<String, String> files;
  int reads = 0;

  @override
  Future<List<String>> pathsContaining(String needle) async =>
      files.entries.where((e) => e.value.contains(needle)).map((e) => e.key).toList();

  @override
  Future<String> read(String path) async {
    reads++;
    return files[path]!;
  }
}

void main() {
  test('TasksService builds index only from files containing the filter', () async {
    final access = _FakeAccess({
      'plan.md': '- [ ] #task A 📅 2026-07-13\n- [ ] kein task',
      'notes.md': '- [x] #task B ✅ 2026-07-01',
      'skill.md': '- [ ] eine skill-checkbox ohne tag', // no #task
    });
    final service = TasksService(access);

    await service.refresh();

    // Only plan.md + notes.md were read (skill.md has no #task).
    expect(access.reads, 2);
    expect(service.tasks.length, 2);
    expect(service.tasks.where((t) => t.done).length, 1);
  });

  test('loading flag toggles around refresh', () async {
    final service = TasksService(_FakeAccess({'a.md': '- [ ] #task x'}));
    expect(service.loading, isFalse);
    final future = service.refresh();
    expect(service.loading, isTrue);
    await future;
    expect(service.loading, isFalse);
    expect(service.tasks.length, 1);
  });
}
