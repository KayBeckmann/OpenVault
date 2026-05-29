import 'dart:typed_data';

// In-memory cache: sessionId → derived vault key (32 bytes).
// Keys live only in RAM — never written to disk.
// Cache entry is removed on logout. Server restart requires re-login.
class SessionKeyCache {
  SessionKeyCache._();
  static final SessionKeyCache instance = SessionKeyCache._();

  final _cache = <String, Uint8List>{};

  void store(String sessionId, Uint8List key) => _cache[sessionId] = key;

  Uint8List? get(String sessionId) => _cache[sessionId];

  void revoke(String sessionId) => _cache.remove(sessionId);

  void revokeAll(String userId, Iterable<String> sessionIds) {
    for (final id in sessionIds) {
      _cache.remove(id);
    }
  }
}
