# Sprint 1.5 — Roster Engine Phase 1

Adds season-aware team roster assignments without removing the legacy `players.team_id` field.

## Features

- Assign available players to a team and season.
- Maintain jersey number, position, captain role, and active status per roster.
- Prevent duplicate player assignments and active jersey-number conflicts.
- Enforce organization consistency across season, team, and player.
- Emit Socket.IO events and record audit entries for roster changes.
- Manage rosters from the new Dashboard **Rosters** workspace.

## API

- `GET /rosters?seasonId=&teamId=`
- `GET /rosters/available?organizationId=&seasonId=&teamId=`
- `POST /rosters`
- `PUT /rosters/:id`
- `DELETE /rosters/:id`
