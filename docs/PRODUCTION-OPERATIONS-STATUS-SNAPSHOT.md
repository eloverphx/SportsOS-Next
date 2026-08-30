# SportsOS Production Operations Status Snapshot

Milestone 29.5 creates one sanitized JSON document representing current operational status.

Generate it with:

```bash
bash scripts/operations-status-snapshot.sh
```

Output is stored under:

```text
data/operations-status/
```

The stable current snapshot is:

```text
data/operations-status/latest.json
```

The snapshot includes the overall reliability state, sanitized reliability issues, latest health/backup/recovery/restore status, and recent pass/fail totals.

It intentionally excludes passwords, tokens, webhook URLs, raw operation logs, backup archive paths, and internal container mount paths.

The default recent-history window is 24 hours.
