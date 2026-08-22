# SportsOS Physical Control Acceptance Checklist

Milestone 14 closes the physical scoreboard input/control path.

## GPIO input acceptance

- Physical controls use a shared control-input contract.
- GPIO bindings are configurable.
- Active-high and active-low inputs are supported.
- Pull-up/input modes are configurable.
- Button debounce is applied before an event is emitted.
- A held button does not repeatedly emit new presses.
- Press and release edges are tracked.

## Control transport acceptance

- Physical button presses create unique input IDs.
- Each press gets a monotonic sequence number.
- Firmware submits control intent to SportsOS.
- Server validates protocol version.
- Server validates control type.
- Server requires VERIFIED device enrollment.
- Server rejects unassigned devices.

## Duplicate/idempotency acceptance

- Same device sequence cannot be applied twice.
- Duplicate replay returns `IGNORED_DUPLICATE`.
- Offline retry reuses the original sequence number.
- Retries cannot create a second authoritative mutation.

## Authoritative execution acceptance

Accepted physical controls map to server-side command intent for:

- home score +1
- home score -1
- away score +1
- away score -1
- clock start
- clock pause
- clock toggle
- period +1
- period -1
- horn trigger

Score, clock, and period actions re-enter the existing SportsOS API mutation path.

The ESP32 does not directly modify authoritative game state.

## Realtime reconciliation acceptance

- Game/device assignment is revalidated after mutation.
- Automatic scoreboard sync remains the sync source of truth.
- Existing dedupe fingerprint is invalidated after physical mutations.
- Physical scoreboard, dashboard, and broadcast surfaces converge on the next authoritative state.

## Horn/output acceptance

- Horn is treated as a physical side-effect.
- Horn does not become persistent game state.
- Horn routes through the existing scoreboard-device command API.
- No duplicate direct MQTT path is introduced.
- Missing device assignment fails safely.

## Audit/diagnostics acceptance

Each physical-control attempt records:

- input ID
- device ID
- game ID when available
- sequence
- input type
- disposition
- command intent
- execution result
- reconciliation result
- error information
- timestamp

Operator diagnostics expose recent accepted, rejected, duplicate, and execution-failed controls.

## Offline/retry acceptance

- Queue capacity is bounded.
- Retry attempts are bounded.
- Retry delay uses bounded exponential backoff.
- `ACCEPTED`, `REJECTED`, and `IGNORED_DUPLICATE` are terminal.
- Only transport/invalid-response failures retry.
- Queue-full and exhausted retries are diagnostic events.

## Final Milestone 14 gate

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-physical-control-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 14 is complete when all commands above are green.
