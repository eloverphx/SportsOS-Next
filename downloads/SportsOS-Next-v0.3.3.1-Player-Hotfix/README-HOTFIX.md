# SportsOS Next v0.3.3.1 Player Hotfix

Fixes:
- DELETE player requests no longer send `Content-Type: application/json` with an empty body.
- MySQL DATE values are normalized to `YYYY-MM-DD` before loading the edit form.
- Player input accepts numeric form values safely and normalizes empty optional values to null.
- PUT validation responses now include field-level details in API logs/network responses.

Overlay the `sportsos_sprint12` folder onto the current SportsOS installation and rebuild the API and dashboard containers.
