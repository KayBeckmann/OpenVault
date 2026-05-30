// Native stub — token is kept in memory only; persistence not needed on native.
class TokenStorage {
  static void save(String token, {bool persistent = false}) {}
  static String? load() => null;
  static bool get isPersistent => false;
  static void clear() {}
}
