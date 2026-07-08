import 'package:flutter/foundation.dart';
import 'addon.dart';
import 'addon_store.dart';
import 'builtin/hello_addon.dart';
import 'builtin/tasks_addon.dart';

/// Central registry of all built-in add-ons and their enabled-state.
///
/// Provided app-wide (see main.dart). Enabled-state is persisted per app
/// (not per vault) for the A1 skeleton — this is one of the open questions in
/// the design doc and can move to per-vault later.
class AddonRegistry extends ChangeNotifier {
  AddonRegistry({List<Addon>? addons})
      : _addons = addons ?? _defaultAddons();

  static List<Addon> _defaultAddons() => [
        TasksAddon(),
        HelloAddon(),
      ];

  final List<Addon> _addons;
  final Map<String, bool> _enabled = {};
  bool _loaded = false;

  List<Addon> get addons => List.unmodifiable(_addons);
  bool get isLoaded => _loaded;

  bool isEnabled(String id) => _enabled[id] ?? false;

  /// Loads persisted state and enables the previously-enabled add-ons.
  Future<void> load() async {
    final stored = await AddonStore.load();
    for (final addon in _addons) {
      final enabled = stored[addon.id] ?? false;
      _enabled[addon.id] = enabled;
      if (enabled) {
        await addon.onEnable(const AddonContext());
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Toggles an add-on, runs its lifecycle hook and persists the new state.
  Future<void> setEnabled(String id, bool value) async {
    final addon = _addons.firstWhere((a) => a.id == id);
    if (_enabled[id] == value) return;
    _enabled[id] = value;
    if (value) {
      await addon.onEnable(const AddonContext());
    } else {
      await addon.onDisable(const AddonContext());
    }
    await AddonStore.save(_enabled);
    notifyListeners();
  }
}
