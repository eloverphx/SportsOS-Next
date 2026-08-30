# Milestone 29.12.2 — Exact Unraid User Scripts Layout Verification

Read-only discovery on the production Unraid host confirmed the SportsOS User Scripts layout.

Each entry contains:

```text
description
name
schedule
script
```

The `schedule` file uses:

```text
custom
<cron expression>
```

The outer `script` file is a small delegate:

```bash
exec bash "/mnt/user/appdata/SportsOS-Next/scripts/unraid-user-script-..."
```

The actual production operation mode is defined in that delegated repository wrapper.

The flash-backed outer files report mode `0600`; therefore executable-bit validation is not a reliable installation check on this host.

Milestone 29.12.2 validates the discovered architecture directly:

- exact entry name;
- SportsOS-managed description;
- exact two-line custom schedule;
- exact delegated wrapper;
- expected operation mode in the repository wrapper;
- live observability execution;
- live recovery execution;
- live alert execution;
- current severity metrics;
- current schema-v2 status snapshot;
- operations history.

No production secrets are read or printed.
