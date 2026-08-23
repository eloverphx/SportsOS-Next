#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.10-streaming-operations-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

DOC="docs/STREAMING-OPERATIONS-ACCEPTANCE.md"
STATUS="docs/MILESTONE-STATUS.md"
TEST="packages/core/test/streaming-operations-acceptance-20.10.test.ts"

for required in \
  ".git" \
  "apps/api/src/services/streamDestinationProfile.ts" \
  "apps/api/src/services/streamDestinationProbe.ts" \
  "apps/api/src/services/encoderSession.ts" \
  "apps/api/src/services/encoderRuntime.ts" \
  "apps/api/src/services/encoderRuntimeAudit.ts" \
  "apps/api/src/services/streamingReadinessPreflight.ts" \
  "apps/api/src/routes/encoderSessions.ts" \
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$DOC" "$STATUS" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p docs "$(dirname "$TEST")"

cat > "$DOC" <<'EOF'
# Streaming Operations Acceptance

Milestone 20.10 closes the first SportsOS streaming-output and encoder-operations sequence.

## Authority boundary

Streaming and encoder operations are operational subsystems. They must never become authoritative for score, clock, period, penalties, game lifecycle, or scoreboard assignment.

Authoritative game state remains in the SportsOS API/game engine.

## Stream destination profile

Each game may have a persisted stream destination profile.

Supported protocols:

```text
RTMP
SRT
```

Supported latency modes:

```text
NORMAL
LOW
ULTRA_LOW
```

Destination states:

```text
DISABLED
CONFIGURED
READY
LIVE
ERROR
```

The public API exposes only redacted stream status. It does not expose ingest URL, credential reference, resolved credential, or stream key.

## Credential boundary

Credential references use server-side references such as:

```text
env://MY_STREAM_KEY
```

Resolved credential values must never be returned by the API or logged by SportsOS.

## Destination readiness probe

Operators may run a server-side reachability check. The probe opens a short TCP connection, records reachability, latency, and timestamp, and marks the destination READY or ERROR.

The probe does not transmit credentials or publish media.

## Encoder session lifecycle

Encoder session states:

```text
STOPPED
STARTING
LIVE
STOPPING
ERROR
```

Start requires a READY stream destination. Stop is operator-controlled and must suppress automatic restart.

## FFmpeg runtime

The encoder runtime uses `spawn()` with `shell: false`, supports a configurable FFmpeg binary path and server-side source URL configuration, supports RTMP/RTMPS FLV output and SRT MPEG-TS output, and sends SIGTERM before SIGKILL fallback.

## Encoder telemetry

SportsOS collects machine-readable FFmpeg progress.

Tracked metrics include frame, FPS, bitrate, total output size, output time, speed, and last progress timestamp.

Publish-health states:

```text
IDLE
STARTING
HEALTHY
STALE
ERROR
```

A runtime with no fresh progress for more than the stale threshold is reported as STALE.

## Automatic recovery

Recovery states:

```text
IDLE
SCHEDULED
RESTARTING
EXHAUSTED
```

Recovery is bounded by maximum restart attempts and restart backoff. Automatic retry stops once attempts are exhausted. Intentional operator stop does not trigger recovery.

## Runtime audit

SportsOS persists encoder runtime history.

Audited events include:

```text
START_REQUESTED
RUNTIME_STARTED
RUNTIME_LIVE
STOP_REQUESTED
RUNTIME_STOPPED
RUNTIME_ERROR
RESTART_SCHEDULED
RESTARTING
RESTART_EXHAUSTED
```

## Streaming readiness preflight

Encoder start is protected by server-side readiness validation.

Checks include:

```text
DESTINATION_PRESENT
DESTINATION_ENABLED
INGEST_URL
CREDENTIAL_REFERENCE
DESTINATION_PROBE
ENCODER_STATE
RECOVERY_STATE
SOURCE_CONFIGURATION
```

Start must return HTTP 409 when readiness fails.

## Operator acceptance sequence

Before production streaming:

1. Select the intended game.
2. Confirm stream destination profile exists.
3. Confirm streaming is enabled.
4. Confirm RTMP/RTMPS or SRT protocol.
5. Confirm ingest URL.
6. Confirm credential reference is server-side and not a raw stream key.
7. Run destination probe.
8. Confirm destination reaches READY.
9. Run Streaming Readiness preflight.
10. Confirm every required check passes.
11. Arm encoder start.
12. Confirm runtime progresses from STARTING to LIVE.
13. Confirm Publish Health becomes HEALTHY.
14. Confirm FPS, bitrate, speed, and last progress update.
15. Confirm runtime history records the start.
16. Stop the encoder.
17. Confirm STOPPED.
18. Confirm no automatic restart occurs after intentional stop.
19. Simulate or observe a controlled runtime failure during testing.
20. Confirm recovery is bounded and audit history explains the failure/retry sequence.

## Required validation

Run:

```bash
npm run typecheck && npm test
```

Then:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

For a real encoder runtime test, the API container also requires `SPORTSOS_ENCODER_SOURCE_URL` or `SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE`, plus the environment variable referenced by the destination `credentialRef`.

## Closeout

Milestones 20.1 through 20.10 establish stream destination profiles, operator destination configuration, safe reachability probing, encoder session state, real FFmpeg process control, telemetry and publish health, bounded automatic recovery, runtime audit history, streaming readiness preflight, and streaming operations acceptance.

Future streaming work should extend these contracts rather than duplicate destination, encoder, telemetry, or readiness logic.
EOF

node <<'NODE'
const fs = require("fs");
const file = "docs/MILESTONE-STATUS.md";
let text = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "# Milestone Status\n";

if (!text.includes("Milestone 20.10 complete")) {
  text += `

### Milestone 20

Streaming output and encoder operations:

- stream destination profile
- stream destination operator UI
- reachability probe
- encoder session model
- FFmpeg runtime adapter
- telemetry and publish health
- automatic recovery policy
- runtime audit history
- streaming readiness preflight
- streaming operations acceptance

## Current streaming checkpoint

\`\`\`text
Milestone 20.10 complete
\`\`\`
`;
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 20.10 streaming operations acceptance", () => {
  const acceptance = fs.readFileSync(
    new URL(
      "../../../docs/STREAMING-OPERATIONS-ACCEPTANCE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const destination = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/streamDestinationProfile.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const runtime = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/encoderRuntime.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/encoderRuntimeAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const preflight = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/streamingReadinessPreflight.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("documents the non-authoritative streaming boundary", () => {
    expect(acceptance).toContain("must never become authoritative");
    expect(acceptance).toContain("Authoritative game state");
  });

  it("retains protected destination credentials", () => {
    expect(destination).toContain("credentialRef");
    expect(acceptance).toContain("must never be returned by the API");
  });

  it("retains FFmpeg runtime and telemetry", () => {
    expect(runtime).toContain("spawn(");
    expect(runtime).toContain("getEncoderTelemetry");
    expect(runtime).toContain("scheduleEncoderRestart");
  });

  it("retains runtime audit history", () => {
    expect(audit).toContain("START_REQUESTED");
    expect(audit).toContain("RESTART_EXHAUSTED");
  });

  it("retains authoritative streaming start preflight", () => {
    expect(preflight).toContain("evaluateStreamingReadiness");
    expect(preflight).toContain("SOURCE_CONFIGURATION");
  });

  it("retains operator readiness, telemetry, recovery, and history UX", () => {
    expect(panel).toContain("Streaming Readiness");
    expect(panel).toContain("Publish Health");
    expect(panel).toContain("Recovery State");
    expect(panel).toContain("Encoder Runtime History");
  });

  it("documents final validation gates", () => {
    expect(acceptance).toContain("npm run typecheck && npm test");
    expect(acceptance).toContain("npm run test:e2e:docker");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - streaming operations acceptance document"
echo "  - credential/security boundary"
echo "  - destination/probe acceptance criteria"
echo "  - encoder runtime/telemetry acceptance criteria"
echo "  - recovery/audit acceptance criteria"
echo "  - streaming readiness acceptance criteria"
echo "  - operator production-stream checklist"
echo "  - Milestone 20 status closeout"
echo "  - closeout regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "FINAL MILESTONE 20 VALIDATION:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "After green:"
echo "  commit and tag Milestone 20."
