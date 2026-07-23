# SportsOS Next — Sprint 1.1

Phase 0 infrastructure plus first-run setup, administrator creation, JWT login, protected dashboard, navigation shell, health cards, and automatic MySQL migrations.

## Upgrade

1. Back up `.env` and your existing Docker volumes.
2. Copy the new repository files over the Phase 0 directory.
3. Add `JWT_SECRET` to `.env` (`openssl rand -hex 32`).
4. Run `docker compose build --no-cache api dashboard`.
5. Run `docker compose up -d`.
6. Visit `http://YOUR_SERVER:4000`; a new database opens the setup wizard.

All application Dockerfiles use `node:22-bookworm` rather than the slim image because the slim image caused npm install failures on the target Unraid host.
