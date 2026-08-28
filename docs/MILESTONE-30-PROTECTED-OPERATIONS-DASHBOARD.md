# Milestone 30 — Protected Operations Dashboard

Milestone 30 completes production deployment of the authenticated SportsOS Operations Dashboard.

## Production acceptance

The deployment was verified with:

- protected operations API enabled;
- operations dashboard enabled;
- dashboard-to-API traffic over the internal Docker network;
- a shared server-side bearer token with no token exposure in public HTML or sampled Next.js JavaScript;
- `/app/data/operations-status/latest.json` readable by the non-root API runtime;
- operations status directory ownership normalized to the API runtime identity;
- snapshot regeneration preserving API-readable permissions;
- unauthenticated operations API requests returning HTTP 403;
- authenticated operations API requests returning HTTP 200;
- public `/dashboard/operations` returning HTTP 200 and rendering healthy operations data;
- Content-Security-Policy present locally and publicly;
- existing security headers preserved.

## Runtime configuration

The deployment expects:

- `SPORTSOS_OPERATIONS_STATUS_API_ENABLED=true`
- `SPORTSOS_OPERATIONS_DASHBOARD_ENABLED=true`
- `SPORTSOS_OPERATIONS_STATUS_TOKEN` configured server-side for both API and dashboard
- `SPORTSOS_API_INTERNAL_URL=http://api:4001`

The token value must remain in runtime configuration only and must never be committed.

## Data permissions

The API runs as a non-root runtime user. The operations status snapshot generator normalizes:

- `data/operations-status` to mode `750`;
- generated JSON files to mode `640`;
- ownership to the API runtime UID/GID.

This prevents scheduled root-owned observability jobs from making the protected status snapshot unreadable by the API.

## Security policy

The dashboard middleware now emits a Content-Security-Policy alongside the existing security headers. The policy restricts default content to the SportsOS origin, blocks framing and object embedding, and allows API/websocket connectivity to `api.crashthenet.online`.

## Release safety

`.env`, runtime `data/`, generated backups, and secret values are excluded from the Milestone 30 release commit.
