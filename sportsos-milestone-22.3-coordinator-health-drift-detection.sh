#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.3-coordinator-health-drift-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-coordinator-health-drift-22.3.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for required in ".git" "$SERVICE" "$ROUTE" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("export type BroadcastCoordinatorHealth")) {
  s += `

export type BroadcastCoordinatorHealth = {
  gameId: string;
  healthy: boolean;
  checkedAt: string;
  issues: Array<{
    id:
      | "INTENT_GO_LIVE_RUNTIME_STOPPED"
      | "INTENT_GO_LIVE_SESSION_NOT_ACTIVE"
      | "INTENT_STOP_RUNTIME_ACTIVE"
      | "GO_LIVE_LIVE_RUNTIME_NOT_LIVE"
      | "EMERGENCY_STOP_RUNTIME_ACTIVE";
    message: string;
  }>;
};

export function evaluateBroadcastCoordinatorHealth(
  gameId: string,
): BroadcastCoordinatorHealth {
  const snapshot =
    getBroadcastCoordinatorSnapshot(
      gameId,
    );

  const issues:
    BroadcastCoordinatorHealth["issues"] = [];

  if (
    snapshot.coordinator.intent ===
      "GO_LIVE" &&
    (
      snapshot.runtime.session.status ===
        "STOPPED" ||
      snapshot.runtime.session.status ===
        "ERROR"
    )
  ) {
    issues.push({
      id:
        "INTENT_GO_LIVE_RUNTIME_STOPPED",
      message:
        \`Coordinator intent is GO_LIVE but encoder runtime is \${snapshot.runtime.session.status}.\`,
    });
  }

  if (
    snapshot.coordinator.intent ===
      "GO_LIVE" &&
    ![
      "ARMED",
      "STARTING",
      "LIVE",
      "DEGRADED",
    ].includes(
      snapshot.goLive.status,
    )
  ) {
    issues.push({
      id:
        "INTENT_GO_LIVE_SESSION_NOT_ACTIVE",
      message:
        \`Coordinator intent is GO_LIVE but go-live session is \${snapshot.goLive.status}.\`,
    });
  }

  if (
    snapshot.coordinator.intent ===
      "STOP" &&
    ![
      "STOPPED",
      "ERROR",
    ].includes(
      snapshot.runtime.session.status,
    )
  ) {
    issues.push({
      id:
        "INTENT_STOP_RUNTIME_ACTIVE",
      message:
        \`Coordinator intent is STOP but encoder runtime is \${snapshot.runtime.session.status}.\`,
    });
  }

  if (
    snapshot.goLive.status ===
      "LIVE" &&
    snapshot.runtime.session.status !==
      "LIVE"
  ) {
    issues.push({
      id:
        "GO_LIVE_LIVE_RUNTIME_NOT_LIVE",
      message:
        \`Go-live session is LIVE but encoder runtime is \${snapshot.runtime.session.status}.\`,
    });
  }

  if (
    snapshot.goLive.status ===
      "EMERGENCY_STOPPED" &&
    ![
      "STOPPED",
      "ERROR",
    ].includes(
      snapshot.runtime.session.status,
    )
  ) {
    issues.push({
      id:
        "EMERGENCY_STOP_RUNTIME_ACTIVE",
      message:
        \`Go-live session is EMERGENCY_STOPPED but encoder runtime is \${snapshot.runtime.session.status}.\`,
    });
  }

  return {
    gameId,
    healthy:
      issues.length ===
      0,
    checkedAt:
      new Date().toISOString(),
    issues,
  };
}
`;
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("evaluateBroadcastCoordinatorHealth")) {
  s=s.replace(
`  getBroadcastCoordinatorSnapshot,
  prepareBroadcastSession,`,
`  evaluateBroadcastCoordinatorHealth,
  getBroadcastCoordinatorSnapshot,
  prepareBroadcastSession,`
  );
}

if(!s.includes('"/broadcast-coordinator/:gameId/health"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Coordinator snapshot route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/health",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          health:
            evaluateBroadcastCoordinatorHealth(
              gameId,
            ),
          snapshot:
            getBroadcastCoordinatorSnapshot(
              gameId,
            ),
        },
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 22.3 — Coordinator health / drift detection

The broadcast coordinator now evaluates whether its intent agrees with the actual go-live and encoder state.

Detected drift includes:

```text
INTENT_GO_LIVE_RUNTIME_STOPPED
INTENT_GO_LIVE_SESSION_NOT_ACTIVE
INTENT_STOP_RUNTIME_ACTIVE
GO_LIVE_LIVE_RUNTIME_NOT_LIVE
EMERGENCY_STOP_RUNTIME_ACTIVE
```

API:

```text
GET /broadcast-coordinator/:gameId/health
```

The health endpoint returns both:

- coordinator drift assessment
- current composed coordinator/go-live/runtime snapshot

Drift detection is observational only. It does not mutate the coordinator, go-live session, encoder runtime, or authoritative game state.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.3 coordinator health / drift detection", () => {
  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines coordinator health",()=> {
    expect(service).toContain("BroadcastCoordinatorHealth");
    expect(service).toContain("evaluateBroadcastCoordinatorHealth");
  });

  it("detects GO_LIVE intent with stopped runtime",()=> {
    expect(service).toContain('"INTENT_GO_LIVE_RUNTIME_STOPPED"');
  });

  it("detects live-session/runtime drift",()=> {
    expect(service).toContain('"GO_LIVE_LIVE_RUNTIME_NOT_LIVE"');
  });

  it("detects emergency-stop runtime drift",()=> {
    expect(service).toContain('"EMERGENCY_STOP_RUNTIME_ACTIVE"');
  });

  it("provides health endpoint",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/health"');
    expect(route).toContain("evaluateBroadcastCoordinatorHealth");
  });

  it("keeps drift detection observational",()=> {
    const start=service.indexOf("export function evaluateBroadcastCoordinatorHealth");
    const block=service.slice(start);
    expect(block).not.toContain("setBroadcastCoordinatorIntent({");
    expect(block).not.toContain("startEncoderRuntime(");
    expect(block).not.toContain("stopEncoderRuntime(");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.3 installed"
echo "============================================================"
echo "Added:"
echo "  - coordinator health evaluator"
echo "  - intent/runtime drift detection"
echo "  - go-live/runtime drift detection"
echo "  - emergency-stop drift detection"
echo "  - observational health API"
echo "  - Milestone 22.3 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 22.4 - Coordinator Reconciliation / Safe Repair Actions"
