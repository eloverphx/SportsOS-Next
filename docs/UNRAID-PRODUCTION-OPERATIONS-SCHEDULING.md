# Unraid Production Operations Scheduling

Milestone 29.11 adds User Scripts-compatible wrappers for the SportsOS production operations system.

It does not modify `/etc/crontab`, call `crontab`, or install a separate scheduler.

## Generated User Scripts

### SportsOS Observability

Recommended custom schedule:

```text
*/5 * * * *
```

Runs:

```bash
bash scripts/run-production-operations.sh observability-refresh
bash scripts/run-production-operations.sh alert
```

### SportsOS Recovery

Recommended custom schedule:

```text
*/5 * * * *
```

Runs:

```bash
bash scripts/run-production-operations.sh recovery
```

### SportsOS Daily Operations

Recommended custom schedule:

```text
15 3 * * *
```

Runs:

```bash
bash scripts/run-production-operations.sh daily
```

### SportsOS Weekly Rehearsal

Recommended custom schedule:

```text
30 4 * * 0
```

Runs:

```bash
bash scripts/run-production-operations.sh weekly
```

## Installation

After Milestone 29.11 tests pass:

```bash
bash scripts/install-unraid-operations-user-scripts.sh
```

The installer expects the Unraid User Scripts plugin directory:

```text
/boot/config/plugins/user.scripts/scripts
```

It only creates or updates the four SportsOS-owned script folders.

After installation, open:

```text
Unraid -> Settings -> User Scripts
```

Verify the generated entries and their custom schedules.

The User Scripts plugin remains responsible for applying those schedules.

## Security

The wrappers contain no passwords, API tokens, webhook URLs, database credentials, or other production secrets. Runtime configuration continues to come from the existing SportsOS environment.
