# SportsOS Production Reliability Alerting

Milestone 29.4 connects the Milestone 29.3 reliability scorecard to the production alerting layer.

Run manually:

```bash
bash scripts/production-reliability-alert-check.sh
```

Or through the operations runner:

```bash
bash scripts/run-production-operations.sh reliability-alert
```

The check:

- runs the local reliability scorecard
- creates a local alert only when the scorecard requires attention
- fingerprints the current issue set
- suppresses duplicate alerts during a cooldown window
- stores local alert state under `data/operations-alerts`
- optionally posts to the existing alert webhook

Default duplicate-alert cooldown:

```text
60 minutes
```

Override with:

```bash
SPORTSOS_RELIABILITY_ALERT_COOLDOWN_MINUTES=120 \
  bash scripts/production-reliability-alert-check.sh
```

An optional reliability-specific webhook can be configured with:

```text
SPORTSOS_RELIABILITY_ALERT_WEBHOOK_URL
```

If that is not defined, the script falls back to:

```text
SPORTSOS_ALERT_WEBHOOK_URL
```

If neither is configured, the alert is still recorded locally.

The reliability alert workflow is diagnostic. It does not restart containers, restore backups, rotate credentials, or apply rollback.
