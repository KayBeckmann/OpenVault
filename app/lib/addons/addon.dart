/// Base contract for a built-in OpenVault add-on (feature module).
///
/// Add-ons are compiled into the app and toggled on/off in settings — not
/// runtime-loaded third-party plugins. See `10_Projects/OpenVault/Add-Ons.md`
/// in the vault for the full design.
abstract class Addon {
  /// Stable identifier, e.g. `tasks`. Used as the persistence key.
  String get id;

  /// Human-readable name shown in the Add-Ons settings screen.
  String get name;

  /// Short description of what the add-on does.
  String get description;

  /// Called when the add-on is enabled (also on startup if already enabled).
  Future<void> onEnable(AddonContext ctx) async {}

  /// Called when the add-on is disabled.
  Future<void> onDisable(AddonContext ctx) async {}
}

/// Runtime context handed to an add-on on enable/disable.
///
/// Intentionally minimal for the A1 skeleton. It grows with each add-on:
/// A2+ will add the vault index, and markdown/view/command registries as the
/// Tasks add-on needs them (see roadmap Phase 12).
class AddonContext {
  const AddonContext();
}
