# SportsOS Scheduled Production Operations

Milestone 29.1 provides a single lock-protected entry point for production maintenance:

```bash
bash scripts/run-production-operations.sh <mode>
```

## Modes

```text
health
alert
recovery
mysql-backup
persistent-backup
backup-all
restore-rehearsal
retention
daily
weekly
```

The runner uses `flock` so two copies of the same operation do not overlap.

Run logs are written under:

```text
data/operations-runs/
```

Lock files are written under:

```text
data/operations-locks/
```

Both directories use restrictive permissions.

## Recommended Unraid User Scripts cadence

These are recommendations only. Milestone 29.1 does not install or modify cron entries.

### Every 5 minutes

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-production-operations.sh alert
```

This already runs the production health monitor and only creates an alert when health checks fail.

### Every 5 minutes

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-production-operations.sh recovery
```

This checks container state and restart deltas. Controlled restart remains opt-in through the existing recovery workflow.

### Daily

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-production-operations.sh daily
```

The daily mode runs:

- alert / health validation
- restart-loop detection
- MySQL backup
- persistent-data backup
- log/report retention

### Weekly

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-production-operations.sh weekly
```

The weekly mode performs:

- isolated backup restore rehearsal
- log/report retention

The restore rehearsal uses a disposable RAM-backed MySQL instance and never restores over production.

## Suggested Unraid User Scripts names

```text
SportsOS - Alert Check
SportsOS - Recovery Check
SportsOS - Daily Operations
SportsOS - Weekly Restore Rehearsal
```

## Safety

The operations runner:

- does not run `docker compose down`
- does not restore over production
- does not rotate credentials
- does not apply Git rollback
- does not automatically enable controlled recovery
- does not install schedules automatically

If a scheduled run fails, inspect:

```text
data/operations-runs/
```
