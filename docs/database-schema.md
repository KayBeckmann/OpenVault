# Database Schema

OpenVault uses SQLite (via the Dart `sqlite3` package) stored at `$DB_PATH` inside the backend container.

## Tables

### `users`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PK | UUID v4 |
| `email` | TEXT | UNIQUE NOT NULL | Login identifier |
| `password_hash` | TEXT | NOT NULL | Argon2id hash of the user's password |
| `argon2_salt` | TEXT | NOT NULL | Per-user salt (base64) used for Argon2id |
| `encryption_salt` | TEXT | NOT NULL | Per-user salt used to derive the vault encryption key via Argon2id |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |

### `vaults`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PK | UUID v4 |
| `user_id` | TEXT | FK → users.id NOT NULL | Owner |
| `name` | TEXT | NOT NULL | Display name (e.g. "My Notes") |
| `remote_url` | TEXT | NOT NULL | Git remote URL (HTTPS or SSH) |
| `clone_path` | TEXT | NOT NULL | Absolute path inside the container (under `$VAULT_ROOT/<user_id>/<vault_id>/`) |
| `last_synced_at` | TEXT | | ISO 8601 timestamp of last successful pull |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |

### `ssh_keys`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PK | UUID v4 |
| `user_id` | TEXT | FK → users.id NOT NULL | Owner |
| `label` | TEXT | NOT NULL | Human-readable name (e.g. "GitHub") |
| `public_key` | TEXT | NOT NULL | OpenSSH public key (plain text — safe to store) |
| `private_key_enc` | TEXT | NOT NULL | AES-256-GCM encrypted private key (base64) |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |

### `sessions`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PK | UUID v4 (also used as JWT `jti`) |
| `user_id` | TEXT | FK → users.id NOT NULL | Owner |
| `issued_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `expires_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `revoked` | INTEGER | NOT NULL DEFAULT 0 | 1 = explicitly invalidated (logout) |

## Notes

- All timestamps are stored as ISO 8601 strings in UTC.
- Foreign keys are enforced (`PRAGMA foreign_keys = ON`).
- The database file itself is NOT encrypted by the app — it is protected by OS-level file permissions and Docker volume access control. Sensitive columns (private keys) are individually encrypted at the application layer.
