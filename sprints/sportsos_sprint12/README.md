# SportsOS Next — Sprint 1.2

Adds production CRUD management for organizations and teams, MinIO-backed logo upload, live Socket.IO refresh, audit activity, search/filter tools, and database-backed dashboard totals.

## Upgrade from Sprint 1.1

1. Back up the repository and Docker volumes.
2. Preserve the existing `.env` file.
3. Copy this release over the existing SportsOS-Next directory.
4. Build application images:
   `docker compose build --no-cache --progress=plain api`
   `docker compose build --no-cache --progress=plain dashboard`
5. Start: `docker compose up -d`
6. Verify: `docker compose ps` and `docker compose logs --tail=100 api dashboard`

The API runs additive migrations at startup and retains existing users, organizations, settings, and audit records. Both Dockerfiles remain pinned to `node:22-bookworm`, which is the image validated on the target Unraid host.

## Sprint 1.2 scope

- Organization create, read, update, delete
- Team create, read, update, delete
- Organization/team colors, status, season, division, sport, and home arena
- PNG, JPEG, WebP, and SVG logo uploads up to 5 MB
- Logo storage in the `sportsos-media` MinIO bucket
- Live refresh events through Socket.IO
- Search and organization filtering
- Live organization/team dashboard totals
- Audit records for all writes
