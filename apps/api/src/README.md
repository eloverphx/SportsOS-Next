# SportsOS Players Module Hotfix

Replace the contents of:

`apps/api/src/modules/players/`

with the four files in the `players` folder.

The changes include:

- fixes the `string | undefined` date-regex TypeScript error
- null-safe MySQL row mapping
- strongly typed player filters
- exact jersey-number search while retaining name search
- safer organization/team relationship validation
- clearer database mapping errors

After copying, rebuild:

```bash
docker compose build --no-cache api
docker compose up -d api
```
