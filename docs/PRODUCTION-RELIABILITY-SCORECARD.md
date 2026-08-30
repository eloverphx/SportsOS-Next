# SportsOS Production Reliability Scorecard

Milestone 29.3 converts production operations history into an actionable local reliability scorecard.

Run:

```bash
bash scripts/operations-reliability-scorecard.sh
```

The scorecard evaluates rolling success percentage, current consecutive failure streak, stale or missing health activity, stale or missing backup activity, and an overall reliability status.

Default thresholds:

```text
Window:                    7 days
Minimum success rate:      95%
Maximum failure streak:    2
Health freshness:          15 minutes
Backup freshness:          36 hours
```

Machine-readable scorecards are stored under:

```text
data/operations-reliability/
```

Exit codes:

```text
0 = reliability healthy
3 = reliability requires attention
```

The scorecard is diagnostic only. It does not restart containers, restore data, rotate credentials, or apply rollback.
