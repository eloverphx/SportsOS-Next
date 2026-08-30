
## Milestone 29.9.1 page repair

The original 29.9 installer successfully updated the schema-v2 snapshot and dashboard helper, but the page insertion failed because the existing JSX did not contain the assumed grid marker.

29.9.1 replaces only the protected operations page with a deterministic implementation that renders:

- normalized severity
- failure rate
- passed/failed run counts
- failure streak
- severity reasons
- latest health
- MySQL backup
- persistent backup
- recovery
- restore rehearsal
- reliability alert
- recent operation totals
- reliability issues

The server-only helper and bearer-token boundary are unchanged.

## Milestone 29.9.1 page repair

The original 29.9 installer successfully updated the schema-v2 snapshot and dashboard helper, but the page insertion failed because the existing JSX did not contain the assumed grid marker.

29.9.1 replaces only the protected operations page with a deterministic implementation that renders:

- normalized severity
- failure rate
- passed/failed run counts
- failure streak
- severity reasons
- latest health
- MySQL backup
- persistent backup
- recovery
- restore rehearsal
- reliability alert
- recent operation totals
- reliability issues

The server-only helper and bearer-token boundary are unchanged.
