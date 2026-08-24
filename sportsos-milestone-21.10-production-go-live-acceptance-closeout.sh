#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.10-production-go-live-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

DOC="docs/GO-LIVE-OPERATIONS-ACCEPTANCE.md"
STATUS="docs/MILESTONE-STATUS.md"
TEST="packages/core/test/production-go-live-acceptance-21.10.test.ts"

for required in \
  ".git" \
  "apps/api/src/services/goLiveSession.ts" \
  "apps/api/src/services/goLiveAudit.ts" \
  "apps/api/src/services/gameDayGoLivePreflight.ts" \
  "apps/api/src/routes/goLiveSessions.ts" \
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx" \
  "docs/GO-LIVE-OPERATIONS.md" \
  "$STATUS"
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
# Production Go-Live Operations Acceptance

Milestone 21.10 closes the first SportsOS production go-live orchestration sequence.

## Authority boundary

Go-live orchestration is operational only.

It must never become authoritative for:

- score
- game clock
- period
- penalties
- game lifecycle
- scoreboard assignment

Authoritative game state remains in the SportsOS game engine and API.

## Go-live lifecycle

Production go-live states:

```text
IDLE
ARMED
STARTING
LIVE
DEGRADED
STOPPING
COMPLETE
ERROR
EMERGENCY_STOPPED
```

Expected production path:

```text
IDLE
  ↓
ARMED
  ↓
STARTING
  ↓
LIVE
  ↓
STOPPING
  ↓
COMPLETE
```

Operational exception paths include:

```text
LIVE → DEGRADED → LIVE
LIVE → DEGRADED → EMERGENCY_STOPPED
STARTING → ERROR
```

## Scheduling

Go-live sessions may define:

- scheduled start
- early start window
- late start window
- optional auto-arm
- auto-arm lead time

Auto-arm may transition only to `ARMED`.

Auto-arm must never start FFmpeg automatically.

## Start-window enforcement

A scheduled start is allowed only while the configured start window is open.

Too-early and expired starts must be rejected.

## Streaming readiness

Go-live arm and start depend on the existing Milestone 20 streaming readiness layer.

Streaming readiness includes:

- destination profile
- destination enabled
- ingest URL
- credential reference
- destination reachability
- encoder availability
- recovery state
- source configuration

## Final game-day preflight

The final game-day preflight includes:

```text
STREAMING_PREFLIGHT
START_WINDOW
GO_LIVE_STATE
EMERGENCY_STOP
DEGRADED_INCIDENT
RECOVERY_EXHAUSTION
ENCODER_AVAILABILITY
SCHEDULE_COUNTDOWN
```

Arming must fail when this final preflight is blocked.

## Health hold

A momentary encoder live state is not sufficient for production confirmation.

The encoder must remain:

```text
session = LIVE
telemetry = HEALTHY
```

for the configured health-hold duration.

Default:

```text
10 seconds
```

Allowed:

```text
0–120 seconds
```

If health is interrupted during the hold, the hold resets.

## Live watchdog

Confirmed production broadcasts are watched for:

- encoder session no longer LIVE
- publish telemetry no longer HEALTHY

If either condition fails, the go-live session becomes:

```text
DEGRADED
```

The watchdog records:

- degraded timestamp
- degradation reason

If runtime health recovers, the go-live session may return to `LIVE`.

## Incident acknowledgement

A degraded incident may be acknowledged by an operator.

Acknowledgement records awareness only.

It must not:

- hide degradation
- clear the degraded state
- claim recovery
- modify game state

Operators may explicitly retry watchdog evaluation after taking corrective action.

## Emergency stop

Emergency stop is the production kill switch.

It:

- suppresses encoder recovery
- stops the encoder runtime
- records timestamp
- records reason
- transitions to `EMERGENCY_STOPPED`

An emergency-stopped session must be reset before another production start.

## Go-live audit

Production lifecycle history is persisted separately from the lower-level encoder runtime audit.

Events include:

```text
ARMED
START_REQUESTED
STARTING
LIVE_CONFIRMED
DEGRADED
RECOVERED
INCIDENT_ACKNOWLEDGED
INCIDENT_RETRY
STOP_REQUESTED
COMPLETE
EMERGENCY_STOP
RESET
ERROR
```

## Operator production acceptance sequence

Before game day:

1. Select the intended game.
2. Confirm stream destination settings.
3. Run destination probe.
4. Confirm stream destination is READY.
5. Configure scheduled start if applicable.
6. Confirm early/late start window.
7. Configure auto-arm if desired.
8. Confirm auto-arm does not start the encoder.
9. Configure confirmation health hold.
10. Run streaming readiness preflight.
11. Run final Game-Day Go-Live Preflight.
12. Confirm all final checks PASS.
13. Arm Go-Live.
14. Start Go-Live during the allowed window.
15. Confirm encoder reaches LIVE.
16. Confirm publish telemetry remains HEALTHY for the configured hold.
17. Confirm production session transitions to LIVE.
18. Confirm watchdog reports healthy state.
19. Test or simulate a controlled degradation.
20. Confirm production session becomes DEGRADED.
21. Acknowledge the incident.
22. Confirm acknowledgement does not falsely clear degradation.
23. Restore runtime health.
24. Retry or allow watchdog evaluation.
25. Confirm session returns to LIVE.
26. Perform normal stop.
27. Confirm COMPLETE.
28. Test emergency stop in a non-production test session.
29. Confirm encoder stops and recovery is suppressed.
30. Confirm session becomes EMERGENCY_STOPPED.
31. Confirm a new start is blocked until reset.
32. Confirm go-live audit history explains the full sequence.

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

For a real streaming runtime test, the Milestone 20 FFmpeg/source/credential configuration must also be present.

## Closeout

Milestones 21.1 through 21.10 establish:

- production go-live session lifecycle
- scheduled start windows
- auto-arm countdown
- continuous health confirmation
- live watchdog and degraded state
- incident acknowledgement
- emergency broadcast stop
- go-live session audit
- final game-day preflight
- production go-live acceptance

Future production-streaming work should extend these contracts rather than duplicate lifecycle, safety, audit, or readiness logic.
EOF

node <<'NODE'
const fs=require("fs");
const file="docs/MILESTONE-STATUS.md";
let text=fs.readFileSync(file,"utf8");

if(!text.includes("Milestone 21.10 complete")) {
  text += `

## Milestone 21 closeout

Production streaming orchestration and game-day go-live:

- production go-live session lifecycle
- scheduled start window
- scheduled auto-arm countdown
- go-live health hold
- live broadcast watchdog
- degraded incident acknowledgement
- emergency broadcast stop
- go-live audit timeline
- final game-day go-live preflight
- production go-live acceptance

\`\`\`text
Milestone 21.10 complete
\`\`\`
`;
}

fs.writeFileSync(file,text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.10 production go-live acceptance", () => {
  const acceptance=fs.readFileSync(
    new URL(
      "../../../docs/GO-LIVE-OPERATIONS-ACCEPTANCE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const session=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/goLiveSession.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/goLiveAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const finalPreflight=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/gameDayGoLivePreflight.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel=fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("documents the non-authoritative go-live boundary",()=> {
    expect(acceptance).toContain("must never become authoritative");
    expect(acceptance).toContain("Authoritative game state remains");
  });

  it("retains production lifecycle and emergency state",()=> {
    for(const state of [
      "ARMED",
      "STARTING",
      "LIVE",
      "DEGRADED",
      "COMPLETE",
      "EMERGENCY_STOPPED",
    ]) {
      expect(session).toContain(`"${state}"`);
    }
  });

  it("retains health-hold and degraded incident state",()=> {
    expect(session).toContain("healthHoldSeconds");
    expect(session).toContain("degradationReason");
    expect(session).toContain("incidentAcknowledgedAt");
  });

  it("retains final game-day preflight",()=> {
    expect(finalPreflight).toContain("evaluateGameDayGoLivePreflight");
    expect(finalPreflight).toContain("EMERGENCY_STOP");
    expect(finalPreflight).toContain("DEGRADED_INCIDENT");
  });

  it("retains production audit history",()=> {
    expect(audit).toContain("go-live-audit.json");
    expect(audit).toContain("EMERGENCY_STOP");
    expect(audit).toContain("INCIDENT_ACKNOWLEDGED");
  });

  it("retains operator production controls",()=> {
    expect(panel).toContain("Production Go-Live");
    expect(panel).toContain("Game-Day Go-Live Preflight");
    expect(panel).toContain("Live Broadcast Watchdog");
    expect(panel).toContain("Emergency Broadcast Stop");
    expect(panel).toContain("Go-Live Session History");
  });

  it("documents final validation gates",()=> {
    expect(acceptance).toContain("npm run typecheck && npm test");
    expect(acceptance).toContain("npm run test:e2e:docker");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 21.10 installed"
echo "============================================================"
echo "Added:"
echo "  - production go-live acceptance document"
echo "  - scheduling/auto-arm acceptance criteria"
echo "  - health hold/watchdog acceptance criteria"
echo "  - incident acknowledgement criteria"
echo "  - emergency-stop acceptance criteria"
echo "  - go-live audit acceptance criteria"
echo "  - final game-day preflight criteria"
echo "  - Milestone 21 status closeout"
echo "  - closeout regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "FINAL MILESTONE 21 VALIDATION:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "After green:"
echo "  commit and tag Milestone 21."
