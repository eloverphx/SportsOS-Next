# Production Reliability Severity & Metrics

Milestone 29.8 adds:

```text
scripts/operations-severity-metrics.sh
```

It reads local operations history and reliability scorecards and writes:

```text
data/operations-metrics/operations-metrics-<timestamp>.json
data/operations-metrics/latest.json
```

Files are mode `0600`.

Severity states:

```text
healthy
warning
critical
```

Default policy:

```text
window:                  24 hours
warning failure rate:     5%
critical failure rate:   20%
warning failure streak:   1
critical failure streak:  3
```

Overrides:

```text
SPORTSOS_OPERATIONS_METRICS_WINDOW_HOURS
SPORTSOS_OPERATIONS_WARNING_FAILURE_RATE
SPORTSOS_OPERATIONS_CRITICAL_FAILURE_RATE
SPORTSOS_OPERATIONS_WARNING_STREAK
SPORTSOS_OPERATIONS_CRITICAL_STREAK
```

Exit codes:

```text
0 = healthy
2 = warning
3 = critical
```

The payload includes normalized run counts, failure rate, current failure streaks, latest per-mode state, severity reasons, and thresholds.

It does not include raw logs, backup paths, credentials, bearer tokens, webhook URLs, or Docker mount metadata.
