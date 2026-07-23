# Sprint 1.3 — Player Engine

This release adds the first complete Player vertical slice.

## Included

- Additive `players` table migration
- Player CRUD API with validation and relationship checks
- Search and filters by organization, team, status, position, name, and jersey number
- Audit events and Socket.IO updates
- Players dashboard page
- Player photo upload using the existing media pipeline
- Active player count on the dashboard

## API

- `GET /players`
- `GET /players/:id`
- `POST /players`
- `PUT /players/:id`
- `DELETE /players/:id`

## Upgrade

Overlay the release on the existing SportsOS directory, preserve `.env`, rebuild `api` and `dashboard`, then restart the stack. The migration is additive and runs automatically during API startup.
