# Milestone 29.12.1 — Unraid Schedule Verifier Repair

The initial 29.12 verifier assumed every Unraid User Scripts installation persisted a custom cron expression in a specific per-entry `schedule` file.

The production host showed that assumption was too strict: all four entries were visible in the Unraid User Scripts UI while the verifier rejected their on-disk metadata.

29.12.1 verifies each entry by:

1. confirming the User Scripts directory exists;
2. confirming its executable wrapper belongs to SportsOS;
3. confirming the expected production-operations mode;
4. accepting the expected cron expression wherever the plugin stores it in entry metadata;
5. when the cron expression is not readable from per-entry files, confirming the installed executable entry and non-empty plugin metadata without inventing a schedule claim.

Runtime observability, recovery, alert, metrics, status, and history checks remain unchanged.
