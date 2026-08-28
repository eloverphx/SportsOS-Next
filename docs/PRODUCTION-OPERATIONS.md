# SportsOS Production Operations

## Milestone 28.1 — Production operations baseline

SportsOS now includes a non-destructive production baseline capture:

```bash
bash scripts/capture-production-baseline.sh
```

The baseline records:

- current branch / commit / release tag
- Docker client/server versions
- running container state
- container image inventory
- local API health
- public dashboard/API reachability
- selected security/deployment checks
- key persistent path metadata

Default output:

```text
data/operations-baselines/production-baseline-<timestamp>.txt
```

Baseline files are mode `600`.

Known secret assignments are defensively redacted before the report is written.

The baseline does not modify containers, databases, DNS, Cloudflare, or persistent application state.

## Milestone 28.2 — Automated MySQL backups

SportsOS now includes:

```bash
bash scripts/backup-mysql.sh
```

Default backup location:

```text
data/backups/mysql/
```

Backup format:

```text
sportsos-mysql-YYYYMMDD-HHMMSS.sql.gz
```

The workflow:

- validates the application MySQL credentials
- uses `mysqldump --single-transaction --quick`
- includes routines, triggers, and events
- compresses the dump with gzip
- validates gzip integrity
- validates that SQL dump content is present
- writes backup files mode `600`
- keeps the backup directory mode `700`
- applies retention automatically

Default retention:

```text
14 days
```

Override:

```text
SPORTSOS_MYSQL_BACKUP_RETENTION_DAYS
```

The MySQL password is passed through `MYSQL_PWD` and is not printed by the script.

## Milestone 28.3 — MinIO / persistent data backups

SportsOS now includes:

```bash
bash scripts/backup-persistent-data.sh
```

Default backup location:

```text
data/backups/persistent/
```

The workflow creates two archives:

```text
sportsos-minio-YYYYMMDD-HHMMSS.tar.gz
sportsos-data-YYYYMMDD-HHMMSS.tar.gz
```

The MinIO archive is created from the actual host mount backing `/data` in the `sportsos_minio` container.

The SportsOS data archive captures the repository `data/` directory while excluding backup and operations-baseline directories to avoid recursive backup growth.

The workflow:

- validates required MinIO environment settings
- locates the actual MinIO host data mount
- creates compressed tar archives
- validates archive integrity
- writes archives mode `600`
- keeps the backup directory mode `700`
- calculates SHA-256 checksums
- applies retention automatically

Default retention:

```text
14 days
```

Override:

```text
SPORTSOS_DATA_BACKUP_RETENTION_DAYS
```

The MinIO password is never printed.

## Milestone 28.4 — Backup restore rehearsal

SportsOS now includes a non-destructive restore rehearsal:

```bash
bash scripts/backup-restore-rehearsal.sh
```

The rehearsal uses the newest available backups and:

- validates MySQL gzip integrity
- validates MinIO/data tar integrity
- extracts MinIO backup into an isolated rehearsal directory
- extracts SportsOS data backup into an isolated rehearsal directory
- creates a temporary MySQL database
- restores the production dump into that temporary database
- verifies that restored tables exist
- drops the temporary database afterward

Default rehearsal workspace:

```text
data/restore-rehearsal/<timestamp>/
```

The live production database is not dropped, replaced, truncated, or restored over.

The temporary database uses a unique `sportsos_restore_rehearsal_*` name and is removed on successful completion or script exit.

## Milestone 28.5 — Production health monitoring

SportsOS now includes:

```bash
bash scripts/production-health-monitor.sh
```

The monitor checks:

- API container
- dashboard container
- MySQL
- Redis
- MQTT
- MinIO
- local `/health` dependency status
- public dashboard/API reachability
- external Socket.IO handshake
- filesystem utilization

Health reports are written to:

```text
data/operations-health/health-<timestamp>.txt
data/operations-health/latest.txt
```

The report directory is mode `700` and reports are mode `600`.

A non-zero exit status means at least one production health check failed.

The monitor is read-only and does not restart containers or change production configuration.

## Milestone 28.6 — Production alerting

SportsOS now includes:

```bash
bash scripts/production-alert-check.sh
```

The alert check runs the production health monitor and:

- generates an incident record when health checks fail
- extracts only failed checks into the alert summary
- stores the latest alert locally
- deduplicates repeated incidents using a SHA-256 fingerprint
- suppresses duplicate alerts during a configurable cooldown window
- optionally sends the alert to a webhook endpoint

Default alert directory:

```text
data/operations-alerts/
```

Default cooldown:

```text
1800 seconds
```

Override:

```text
SPORTSOS_ALERT_COOLDOWN_SECONDS
```

Optional webhook:

```text
SPORTSOS_ALERT_WEBHOOK_URL
```

If no webhook is configured, incidents are still recorded locally.

The alert directory is mode `700`; state and alert files are mode `600`.

The alert script does not restart services or change production configuration.

## Milestone 28.7 — Container recovery / restart-loop detection

SportsOS now includes:

```bash
bash scripts/container-recovery-check.sh
```

The check tracks:

- container runtime status
- container health status
- Docker restart counts
- restart-count changes between runs

Default restart-loop threshold:

```text
3 new restarts between checks
```

Override:

```text
SPORTSOS_RESTART_LOOP_THRESHOLD
```

State is stored at:

```text
data/operations-recovery/restart-counts.env
```

By default the check is read-only.

Optional controlled recovery:

```bash
SPORTSOS_APPLY_RECOVERY=1 \
  bash scripts/container-recovery-check.sh
```

When enabled, a detected restart loop triggers one `docker compose restart <service>` for the affected service. It never performs `docker compose down` or destructive stack-wide recovery.

## Milestone 28.8 — Log retention / rotation

SportsOS now includes:

```bash
bash scripts/log-retention-check.sh
```

The workflow checks:

- Docker log driver for production containers
- current Docker log file size when available
- whether Compose exposes explicit `max-size` / `max-file` rotation settings
- storage usage for SportsOS operations/backups
- retention of old operations reports

Default maximum observed container-log size:

```text
100 MB
```

Override:

```text
SPORTSOS_MAX_CONTAINER_LOG_MB
```

Default operations-report retention:

```text
30 days
```

Override:

```text
SPORTSOS_REPORT_RETENTION_DAYS
```

Old operations reports are deleted by age. Backup retention remains governed by the dedicated MySQL and persistent-data backup scripts.

The log-retention workflow never truncates active Docker log files.

## Milestone 28.8 — Log retention / rotation

SportsOS now includes:

```bash
bash scripts/log-retention-check.sh
```

The workflow checks:

- Docker log driver for production containers
- current Docker log file size when available
- whether Compose exposes explicit `max-size` / `max-file` rotation settings
- storage usage for SportsOS operations/backups
- retention of old operations reports

Default maximum observed container-log size:

```text
100 MB
```

Override:

```text
SPORTSOS_MAX_CONTAINER_LOG_MB
```

Default operations-report retention:

```text
30 days
```

Override:

```text
SPORTSOS_REPORT_RETENTION_DAYS
```

Old operations reports are deleted by age. Backup retention remains governed by the dedicated MySQL and persistent-data backup scripts.

The log-retention workflow never truncates active Docker log files.

## Milestone 28.9 — Production rollback workflow

SportsOS now includes:

```bash
bash scripts/production-rollback.sh
```

Default rollback target:

```text
sportsos-m27-complete
```

Override:

```text
SPORTSOS_ROLLBACK_TARGET
```

The workflow:

- validates that the target resolves to a Git commit
- refuses to operate on a dirty working tree
- captures a production baseline
- creates a MySQL backup
- creates persistent-data backups
- performs no checkout by default
- can optionally detach HEAD at the known-good rollback commit
- rebuilds only API/dashboard application services
- validates production health afterward

Dry-run is the default.

Apply explicitly:

```bash
SPORTSOS_APPLY_ROLLBACK=1 \
SPORTSOS_ROLLBACK_TARGET=sportsos-m27-complete \
  bash scripts/production-rollback.sh
```

The rollback workflow does not automatically restore database or MinIO data. Data restoration remains a separate, deliberate disaster-recovery operation.

## Milestone 28.10 — Disaster recovery rehearsal / operations closeout

Final operations acceptance command:

```bash
bash scripts/operations-closeout-rehearsal.sh
```

The workflow combines:

- fresh backup creation
- isolated restore validation
- production health verification
- alert-path verification
- container recovery validation
- log-retention verification
- rollback dry-run
- typecheck/unit/E2E tests

It is intentionally non-destructive to live production data and configuration.

Closeout documentation:

```text
docs/MILESTONE-28-PRODUCTION-OPERATIONS-CLOSEOUT.md
```
