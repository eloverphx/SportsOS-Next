# Sprint 1.4 — Season Engine

Adds organization-scoped seasons as first-class records for future rosters, schedules, games, standings, and statistics.

## API
- `GET /seasons`
- `GET /seasons/:id`
- `POST /seasons`
- `PUT /seasons/:id`
- `DELETE /seasons/:id`

## Dashboard
- New `/seasons` workspace
- Organization filtering and text search
- Create, edit, activate/deactivate, and delete seasons
- Live Socket.IO refresh

## Reliability changes
- Dashboard API helper no longer sends `Content-Type: application/json` for bodyless DELETE requests.
- Season dates are normalized to `YYYY-MM-DD`.
- End dates are validated against start dates.
