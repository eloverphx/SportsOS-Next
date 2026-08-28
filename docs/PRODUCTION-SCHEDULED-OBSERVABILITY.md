# Scheduled Production Observability

Milestone 29.10 makes the Milestone 29 severity pipeline refreshable as one production operation.

New command:

```bash
bash scripts/run-production-operations.sh observability-refresh
```

The refresh sequence is:

```text
operations-severity-metrics.sh
        |
        v
data/operations-metrics/latest.json
        |
        v
operations-status-snapshot.sh
        |
        v
data/operations-status/latest.json
```

Severity metrics intentionally use these exit codes:

```text
0 = healthy
2 = warning
3 = critical
```

All three are valid generated states. The observability refresh therefore continues to the status snapshot for exit codes 0, 2, and 3.

Any other metrics exit code is treated as an execution failure and is propagated.

The existing production operations runner also retains its fail-fast child-command behavior from Milestone 29.7.3.

## Suggested Unraid User Scripts cadence

The existing frequent alert/recovery checks may remain unchanged.

Run the observability refresh every five minutes:

```bash
cd /mnt/user/appdata/SportsOS-Next &&
bash scripts/run-production-operations.sh observability-refresh
```

The `daily` operations mode is also patched to refresh observability after its existing daily work, providing an additional guaranteed snapshot update.

No schedule is installed automatically by this milestone.
