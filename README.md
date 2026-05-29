# OpenVault

Self-hosted, Git-synchronized Obsidian-compatible Markdown vault — accessible in the browser and as native app on Android, Linux, and Windows.

> **Status:** Active development — Phase 1 (Setup) complete.

## Features

- **Obsidian-compatible** — `[[Wikilinks]]`, Backlinks, Tags, YAML Frontmatter, Callouts
- **Git as source of truth** — your vault stays a normal Git repo (GitHub, GitLab, Gitea/Forgejo)
- **Multi-platform** — Flutter Web (browser), Android, Linux, Windows
- **Self-hosted** — Docker Compose deployment, no cloud lock-in
- **User isolation** — every user manages their own vault, no cross-user access
- **Encrypted at rest** — AES-256-GCM, key derived from user password via Argon2id
- **MIT License** — fully open source

## Architecture

```
Native Apps (Android / Linux / Windows)
└── Flutter App
    └── Git directly (libgit2 via FFI) ──→ GitHub / GitLab / Gitea

Web App
└── Flutter Web (Browser)
    └── Backend API (Dart/Shelf) ──→ Git operations (server-side)
                                 └── Vault files (AES-256 encrypted on disk)
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Frontend | Flutter (Dart) — all platforms |
| Backend | Dart (Shelf) — Web App only |
| Markdown Editor | Custom (full Obsidian syntax support) |
| Git (native) | libgit2 via FFI (`libgit2dart`) |
| Git (web) | shell `git` in backend container |
| Auth | JWT + SQLite user DB |
| Encryption | AES-256-GCM, key via Argon2id |
| Deployment | Docker Compose |

## Quick Start (Web App)

**Requirements:** Docker, Docker Compose

```bash
git clone https://github.com/KayBeckmann/OpenVault.git
cd OpenVault
cp .env.example .env
# Edit .env — set JWT_SECRET and ENCRYPTION_KEY (see comments in file)
docker compose up -d
```

Open `http://localhost:8080` in your browser.

## Configuration

Copy `.env.example` to `.env` and set the required values:

| Variable | Required | Description |
|----------|----------|-------------|
| `JWT_SECRET` | ✅ | JWT signing secret — `openssl rand -base64 64` |
| `ENCRYPTION_KEY` | ✅ | AES-256 key for vault encryption — `openssl rand -hex 32` |
| `FRONTEND_PORT` | — | Port for the web frontend (default: `8080`) |
| `BACKEND_PORT` | — | Port for the backend API (default: `8090`) |
| `ARGON2_SALT_ROUNDS` | — | Argon2id iterations (default: `3`, recommended: `4–8`) |

## Development

**Requirements:** Flutter 3.x, Dart 3.x

```bash
# Frontend (Flutter)
cd app
flutter pub get
flutter run -d chrome          # Web
flutter run -d linux           # Linux desktop
flutter run                    # Connected device

# Backend (Dart/Shelf)
cd backend
dart pub get
dart run bin/server.dart
```

## Design System

OpenVault uses the **Obsidian Flux** design system — a dark-first, Material Design 3 compatible color scheme with Space Grotesk (UI), Inter (body), and JetBrains Mono (editor).

Full specification: [`Vorlagen/obsidian_flux/DESIGN.md`](Vorlagen/obsidian_flux/DESIGN.md)

## Roadmap

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Architecture & Setup | ✅ Done |
| 2 | Authentication & User Management | 🔄 Next |
| 3 | SSH Key Management | ⏳ Planned |
| 4 | Git Integration | ⏳ Planned |
| 5 | File Browser | ⏳ Planned |
| 5b | Tags & Filter | ⏳ Planned |
| 6 | Markdown Editor | ⏳ Planned |
| 7 | Encrypted Backend | ⏳ Planned |
| 8 | Docker Deployment | ⏳ Planned |
| 9 | Platform Tests | ⏳ Planned |

Full task list: [`TODO.md`](TODO.md) in the Obsidian Vault project notes.

## Documentation

- [Database Schema](docs/database-schema.md)
- [Encryption Concept](docs/encryption.md)
- [Design System](Vorlagen/obsidian_flux/DESIGN.md)

## License

MIT — see [LICENSE](LICENSE)
