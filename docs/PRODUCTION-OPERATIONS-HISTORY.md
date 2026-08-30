# SportsOS Production Operations History

Milestone 29.2 adds machine-readable history for scheduled production operations.

Each invocation of:

```bash
bash scripts/run-production-operations.sh <mode>
```

writes a JSON status record under:

```text
data/operations-history/
```

Each record includes the mode, completion status, exit code, timestamp, and the path to its full raw operation log.

## Trend report

Run:

```bash
bash scripts/operations-history-report.sh
```

The default reporting window is seven days.

For a different window:

```bash
SPORTSOS_OPERATIONS_HISTORY_DAYS=30 \
  bash scripts/operations-history-report.sh
```

The report summarizes runs by mode, passed runs, failed runs, latest status, and recent failures.

History remains local and is not exposed through a public API.
