# SportsOS Firmware Fleet Acceptance Checklist

Milestone 13 closes the firmware-fleet-management software path.

## Release acceptance

- OTA release manifest can be created.
- Release contains SHA-256 and firmware size.
- Release can be registered in SportsOS.
- Artifact import rejects invalid size.
- Artifact import rejects invalid SHA-256.
- Valid artifact is stored by SportsOS.

## Device-offer acceptance

- Device must be VERIFIED.
- Device must belong to an ACTIVE rollout.
- Rollout release must exist.
- Channel must match.
- hardware target must match.
- Device already on target version receives no update.
- Eligible device receives a device-bound artifact URL.

## OTA staging acceptance

- Firmware downloads from SportsOS.
- HTTP failures abort.
- size mismatches abort.
- SHA-256 mismatch aborts.
- OTA partition is finalized only after integrity verification.

## Install policy acceptance

- Unverified device cannot install.
- Unsafe live runtime blocks install.
- Staged image is required.
- Boot is marked pending validation before restart.
- Successful authoritative startup confirms boot healthy.

## Reporting acceptance

- Update reports require VERIFIED device identity.
- Progress can be recorded.
- failures can include error details.
- latest deployment state can be queried per device.
- report history is retained.

## Rollout acceptance

- Rollout starts as DRAFT.
- ACTIVE rollout offers updates.
- PAUSED rollout stops new offers.
- ACTIVE rollout can be completed.
- DRAFT/ACTIVE/PAUSED rollout can be cancelled.
- All targets must be VERIFIED devices.

## Dashboard acceptance

`/scoreboards/firmware` shows:

- release inventory
- rollout plans
- rollout controls
- current firmware version
- target firmware version
- deployment progress
- deployment failures

## Final Milestone 13 gate

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-fleet-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 13 is complete when all commands above are green.
