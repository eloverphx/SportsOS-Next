# SportsOS Core

`@sportsos/core` contains shared platform contracts and utilities used by SportsOS applications and modules.

## Responsibilities

The package may contain:

- shared API response contracts
- shared health and pagination types
- domain-event contracts
- application error classes
- validation schemas
- logging interfaces
- audit metadata

## Boundaries

Sports-specific business logic does not belong in this package.

The following concepts should remain in their respective feature modules:

- games
- teams
- players
- seasons
- rosters
- venues
- officials
- penalties
- scoring
- streaming
- hardware

## Build

```bash
npm install
npm run typecheck
npm run build