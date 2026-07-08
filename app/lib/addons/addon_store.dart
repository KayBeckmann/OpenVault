// Cross-platform persistence of add-on enabled-state.
// Web → browser localStorage; native → JSON file in app support dir.
// Mirrors the conditional-import pattern used by token_storage.dart.
export 'addon_store_io.dart' if (dart.library.html) 'addon_store_web.dart';
