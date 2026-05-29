# Encryption Concept

## Goals

1. Vault files are unreadable on disk without the user's password.
2. The encryption key is never stored — it lives only in RAM during an active session.
3. If the server is compromised (disk image stolen), vault contents remain confidential.

## Key Derivation

```
user_password + encryption_salt (per-user, stored in DB)
        │
        ▼  Argon2id (m=65536, t=3, p=1)
        │
   vault_key (32 bytes)    ← held in RAM, never written to disk
```

- **Algorithm:** Argon2id (winner of the Password Hashing Competition)
- **Parameters:** `m=65536` (64 MB memory), `t=3` iterations, `p=1` parallelism
- **Salt:** 16-byte random salt generated once per user at registration, stored in `users.encryption_salt`

## Vault Encryption at Rest

```
plaintext_file
        │
        ▼  AES-256-GCM
        │  key  = vault_key
        │  nonce = 12-byte random per file write
        │  aad   = file path relative to vault root
        │
   encrypted_blob  =  nonce (12 B) || ciphertext || auth_tag (16 B)
```

- **Algorithm:** AES-256-GCM (authenticated encryption)
- **Nonce:** Fresh random 12 bytes per write — never reused
- **AAD (Additional Authenticated Data):** The relative file path binds each blob to its location, preventing ciphertext-swapping attacks

## SSH Private Key Encryption

SSH private keys use the same AES-256-GCM scheme but with the global `ENCRYPTION_KEY` from the environment (not the user's derived key). This allows the backend to use SSH keys without requiring the user to be logged in (e.g. for automated pulls).

```
env ENCRYPTION_KEY (32 bytes, from .env)
        │
        ▼  AES-256-GCM (nonce per write)
        │
   private_key_enc  stored in ssh_keys.private_key_enc
```

## Password Change

When a user changes their password:

1. Derive the old `vault_key` using the old password + stored `encryption_salt`.
2. Decrypt all vault files with the old key.
3. Generate a new `encryption_salt`.
4. Derive a new `vault_key` from the new password + new salt.
5. Re-encrypt all vault files with the new key.
6. Store the new `encryption_salt`, new `password_hash`, and new `argon2_salt`.

This operation is atomic — a failure mid-way leaves the old key valid until completion.

## What is NOT Encrypted

| Item | Reasoning |
|------|-----------|
| `users.email` | Required for login lookup |
| `users.password_hash` | The hash is the protection mechanism |
| `vaults.name`, `remote_url` | Metadata, not content |
| `ssh_keys.public_key` | Public by definition |
| Database file itself | Protected by OS permissions + Docker; individual sensitive fields are encrypted |
