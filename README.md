# SportsOS v0.3.4 Season Engine Overlay

Overlay these files onto the root of the existing SportsOS v0.3.3.2 project.

Then rebuild:

```bash
docker compose build --no-cache api dashboard
docker compose up -d
```

Verify:

```bash
curl http://YOUR_UNRAID_IP:4001/version
```

Expected package version: `0.3.4-season-engine`.

Test in the dashboard:

1. Open **Seasons**.
2. Create a season.
3. Edit the season dates and active status.
4. Delete a season.
5. Confirm the Recent Activity panel receives season events.
