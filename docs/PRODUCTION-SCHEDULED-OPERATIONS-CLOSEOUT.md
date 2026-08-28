# Scheduled Production Operations Closeout

Milestone 29.12 verifies that the SportsOS production automation layer is actually installed and executable on Unraid.

Run:

```bash
bash scripts/verify-scheduled-production-operations.sh
```

The verifier checks:

- SportsOS Observability User Script exists
- observability schedule is every 5 minutes
- SportsOS Recovery User Script exists
- recovery schedule is every 5 minutes
- SportsOS Daily Operations is scheduled for 03:15
- SportsOS Weekly Rehearsal is scheduled for Sunday 04:30
- observability refresh executes successfully
- recovery check executes successfully
- alert check executes successfully
- schema-v2 operations status snapshot exists
- severity metrics snapshot exists
- operations history contains JSON run records

Reports are stored under:

```text
data/operations-scheduled-verification/
```

Report files are mode `0600`.

A passing verification demonstrates that the Milestone 29 operations observability and scheduling stack is installed and locally executable. It does not require waiting for the next scheduled cron occurrence; future run history will confirm continuing schedule execution.
