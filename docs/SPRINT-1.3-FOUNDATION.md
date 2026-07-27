# Sprint 1.3 Foundation Refactor

This release is a behavior-preserving API refactor that prepares SportsOS for the Player Engine.

## Changes

- Reduced `apps/api/src/server.ts` to startup only.
- Added central environment validation.
- Separated MySQL, MinIO, migrations, and Socket.IO infrastructure.
- Separated authentication, setup, organizations, teams, media, and system routes.
- Added reusable authentication, audit, and media helpers.
- Preserved all Sprint 1.2 endpoints and database tables.

## Upgrade

Overlay this release onto Sprint 1.2, keep the existing `.env`, then rebuild the API and dashboard.

```bash
cd /mnt/user/appdata/SportsOS-Next
docker compose build --no-cache api dashboard
docker compose up -d
docker compose logs -f api dashboard
```

## Verification

- `/health` reports all services online.
- Existing administrator login still works.
- Organizations and teams remain visible.
- Creating, editing, and deleting organizations and teams works.
- Logo upload and display still work.
- Dashboard counts and audit activity still work.
