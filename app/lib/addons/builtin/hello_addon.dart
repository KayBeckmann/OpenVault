import 'package:flutter/foundation.dart';
import '../addon.dart';

/// Minimal demo add-on that proves the A1 infrastructure end-to-end:
/// it appears in the Add-Ons screen, toggles, persists and runs its lifecycle
/// hooks. No user-facing behaviour beyond a debug log yet.
class HelloAddon extends Addon {
  @override
  String get id => 'hello';

  @override
  String get name => 'Hello (Demo)';

  @override
  String get description =>
      'Demo-Add-On zum Testen der Add-On-Infrastruktur. Ohne Funktion — '
      'das Tasks-Add-On folgt als erstes echtes Modul.';

  @override
  Future<void> onEnable(AddonContext ctx) async {
    debugPrint('[addon:hello] enabled');
  }

  @override
  Future<void> onDisable(AddonContext ctx) async {
    debugPrint('[addon:hello] disabled');
  }
}
