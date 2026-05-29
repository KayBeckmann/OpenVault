import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../models/user.dart';
import 'crypto_service.dart';
import 'session_key_cache.dart';
import 'vault_crypto_service.dart';

const _uuid = Uuid();

final _jwtSecret = Platform.environment['JWT_SECRET'] ?? 'dev-secret-change-in-production';
const _tokenTtl = Duration(hours: 24);

String _now() => DateTime.now().toUtc().toIso8601String();

class AuthService {
  Future<Map<String, dynamic>> register(String email, String password) async {
    _validateEmail(email);
    _validatePassword(password);

    final existing = db.select('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.isNotEmpty) {
      throw AuthException('Email already registered', 409);
    }

    final id = _uuid.v4();
    final pbkdf2Salt = generateSalt();
    final encryptionSalt = generateSalt();
    final passwordHash = hashPassword(password, pbkdf2Salt);
    final now = _now();

    db.execute(
      'INSERT INTO users (id, email, password_hash, pbkdf2_salt, encryption_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, email, passwordHash, pbkdf2Salt, encryptionSalt, now, now],
    );

    final user = User(
      id: id,
      email: email,
      passwordHash: passwordHash,
      pbkdf2Salt: pbkdf2Salt,
      encryptionSalt: encryptionSalt,
      createdAt: now,
      updatedAt: now,
    );

    final (token, sessionId) = _issueToken(user.id);
    _cacheVaultKey(sessionId, password, encryptionSalt);
    return {'user': user.toPublicJson(), 'token': token};
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final rows = db.select('SELECT * FROM users WHERE email = ?', [email]);
    if (rows.isEmpty) {
      throw AuthException('Invalid credentials', 401);
    }

    final user = User.fromRow(rows.first);
    final valid = verifyPassword(password, user.pbkdf2Salt, user.passwordHash);
    if (!valid) {
      throw AuthException('Invalid credentials', 401);
    }

    final (token, sessionId) = _issueToken(user.id);
    _cacheVaultKey(sessionId, password, user.encryptionSalt);
    return {'user': user.toPublicJson(), 'token': token};
  }

  void logout(String sessionId) {
    db.execute('UPDATE sessions SET revoked = 1 WHERE id = ?', [sessionId]);
    SessionKeyCache.instance.revoke(sessionId);
  }

  // Returns (user, sessionId) — sessionId needed to look up vault key cache
  (User, String)? getUserAndSessionFromToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;
      final sessionId = payload['jti'] as String?;
      final userId = payload['sub'] as String?;
      if (sessionId == null || userId == null) return null;

      final sessionRows = db.select(
        'SELECT * FROM sessions WHERE id = ? AND user_id = ? AND revoked = 0 AND expires_at > ?',
        [sessionId, userId, _now()],
      );
      if (sessionRows.isEmpty) return null;

      final userRows = db.select('SELECT * FROM users WHERE id = ?', [userId]);
      if (userRows.isEmpty) return null;

      return (User.fromRow(userRows.first), sessionId);
    } catch (_) {
      return null;
    }
  }

  User? getUserFromToken(String token) => getUserAndSessionFromToken(token)?.$1;

  (String token, String sessionId) _issueToken(String userId) {
    final sessionId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final expires = now.add(_tokenTtl);

    db.execute(
      'INSERT INTO sessions (id, user_id, issued_at, expires_at) VALUES (?, ?, ?, ?)',
      [sessionId, userId, now.toIso8601String(), expires.toIso8601String()],
    );

    final jwt = JWT({'sub': userId}, jwtId: sessionId);
    final token = jwt.sign(SecretKey(_jwtSecret), expiresIn: _tokenTtl);
    return (token, sessionId);
  }

  void _cacheVaultKey(String sessionId, String password, String encryptionSalt) {
    if (Platform.environment['ENCRYPT_VAULTS'] != '1') return;
    final key = deriveKey(password, encryptionSalt);
    SessionKeyCache.instance.store(sessionId, key);
  }

  void _validateEmail(String email) {
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      throw AuthException('Invalid email format', 400);
    }
  }

  void _validatePassword(String password) {
    if (password.length < 8) {
      throw AuthException('Password must be at least 8 characters', 400);
    }
  }
}

class AuthException implements Exception {
  final String message;
  final int statusCode;
  const AuthException(this.message, this.statusCode);
}
