import '../addon.dart';

/// The Tasks add-on: renders ```tasks query blocks against a vault-wide index
/// (Obsidian-compatible). Toggling it on/off controls whether the index is
/// built and whether task blocks show results. See lib/addons/tasks/.
class TasksAddon extends Addon {
  @override
  String get id => 'tasks';

  @override
  String get name => 'Tasks';

  @override
  String get description =>
      'Obsidian-kompatible Aufgaben: ```tasks-Blöcke rendern offene/erledigte '
      'Aufgaben aus dem ganzen Vault (Filter „#task", 📅 Fälligkeit, Priorität).';
}
