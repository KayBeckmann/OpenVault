import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

// On Debian/Ubuntu the versioned SO is libsqlite3.so.0, not libsqlite3.so
void _overrideSqliteLibraryIfNeeded() {
  if (!Platform.isLinux) return;
  const versioned = '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0';
  if (File(versioned).existsSync()) {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open(versioned));
  }
}

Database? _db;

Database get db {
  _db ??= _open();
  return _db!;
}

Database _open() {
  _overrideSqliteLibraryIfNeeded();
  final path = Platform.environment['DB_PATH'] ?? 'openvault.db';
  final database = sqlite3.open(path);
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = WAL');
  _migrate(database);
  return database;
}

void _migrate(Database d) {
  d.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      pbkdf2_salt TEXT NOT NULL,
      encryption_salt TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  d.execute('''
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      issued_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      revoked INTEGER NOT NULL DEFAULT 0,
      remember_me INTEGER NOT NULL DEFAULT 0
    )
  ''');
  try {
    d.execute('ALTER TABLE sessions ADD COLUMN remember_me INTEGER NOT NULL DEFAULT 0');
  } catch (_) {}

  d.execute('''
    CREATE TABLE IF NOT EXISTS vaults (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      remote_url TEXT NOT NULL,
      clone_path TEXT NOT NULL,
      ssh_key_id TEXT REFERENCES ssh_keys(id) ON DELETE SET NULL,
      last_synced_at TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  // Migration: add ssh_key_id column if missing (for existing databases)
  try {
    d.execute('ALTER TABLE vaults ADD COLUMN ssh_key_id TEXT REFERENCES ssh_keys(id) ON DELETE SET NULL');
  } catch (_) {}

  // Migration: add auto_push_on_close to vault_settings if missing
  try {
    d.execute('ALTER TABLE vault_settings ADD COLUMN auto_push_on_close INTEGER NOT NULL DEFAULT 0');
  } catch (_) {}

  // Migration: add template_folders (JSON map: template name -> target folder)
  try {
    d.execute("ALTER TABLE vault_settings ADD COLUMN template_folders TEXT NOT NULL DEFAULT '{}'");
  } catch (_) {}

  d.execute('''
    CREATE TABLE IF NOT EXISTS vault_settings (
      vault_id TEXT PRIMARY KEY REFERENCES vaults(id) ON DELETE CASCADE,
      template_folder TEXT NOT NULL DEFAULT '_templates',
      default_note_folder TEXT NOT NULL DEFAULT '',
      auto_push_on_close INTEGER NOT NULL DEFAULT 0,
      template_folders TEXT NOT NULL DEFAULT '{}'
    )
  ''');

  d.execute('''
    CREATE TABLE IF NOT EXISTS ssh_keys (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      label TEXT NOT NULL,
      public_key TEXT NOT NULL,
      private_key_enc TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
}
