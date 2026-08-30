#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.9-preflight-recovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/gameDayGoLivePreflight.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/game-day-go-live-preflight-21.9.test.ts"
DOC="docs/GO-LIVE-OPERATIONS.md"

for required in \
  ".git" \
  "apps/api/src/services/goLiveSession.ts" \
  "apps/api/src/services/streamingReadinessPreflight.ts" \
  "apps/api/src/services/encoderRuntime.ts" \
  "$ROUTE" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import {
  encoderRuntimeSnapshot,
} from "./encoderRuntime.js";

import {
  evaluateGoLiveCountdown,
  evaluateGoLiveStartWindow,
  getGoLiveSession,
} from "./goLiveSession.js";

import {
  evaluateStreamingReadiness,
} from "./streamingReadinessPreflight.js";

export type GameDayGoLiveCheck = {
  id:
    | "STREAMING_PREFLIGHT"
    | "START_WINDOW"
    | "GO_LIVE_STATE"
    | "EMERGENCY_STOP"
    | "DEGRADED_INCIDENT"
    | "RECOVERY_EXHAUSTION"
    | "ENCODER_AVAILABILITY"
    | "SCHEDULE_COUNTDOWN";
  passed: boolean;
  message: string;
};

export type GameDayGoLivePreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: GameDayGoLiveCheck[];
};

export function evaluateGameDayGoLivePreflight(
  gameId: string,
): GameDayGoLivePreflight {
  const session =
    getGoLiveSession(
      gameId,
    );

  const streaming =
    evaluateStreamingReadiness(
      gameId,
    );

  const startWindow =
    evaluateGoLiveStartWindow(
      gameId,
    );

  const countdown =
    evaluateGoLiveCountdown(
      gameId,
    );

  const runtime =
    encoderRuntimeSnapshot(
      gameId,
    );

  const allowedState =
    session.status === "IDLE" ||
    session.status === "ARMED" ||
    session.status === "COMPLETE" ||
    session.status === "ERROR";

  const checks:
    GameDayGoLiveCheck[] = [
      {
        id:
          "STREAMING_PREFLIGHT",
        passed:
          streaming.ready,
        message:
          streaming.ready
            ? "Streaming readiness preflight passes."
            : "Streaming readiness preflight is blocked.",
      },
      {
        id:
          "START_WINDOW",
        passed:
          startWindow.withinWindow,
        message:
          startWindow.withinWindow
            ? "Go-live start window is open."
            : startWindow.tooEarly
              ? "Go-live start window has not opened yet."
              : "Go-live start window has expired.",
      },
      {
        id:
          "GO_LIVE_STATE",
        passed:
          allowedState,
        message:
          allowedState
            ? `Go-live state ${session.status} is eligible for preparation.`
            : `Go-live state ${session.status} is not eligible for a new start.`,
      },
      {
        id:
          "EMERGENCY_STOP",
        passed:
          session.status !==
          "EMERGENCY_STOPPED",
        message:
          session.status ===
            "EMERGENCY_STOPPED"
            ? "Emergency-stopped session must be reset."
            : "No emergency-stop lock is active.",
      },
      {
        id:
          "DEGRADED_INCIDENT",
        passed:
          session.status !==
          "DEGRADED",
        message:
          session.status ===
            "DEGRADED"
            ? session.degradationReason ??
              "Live incident remains degraded."
            : "No degraded live incident is active.",
      },
      {
        id:
          "RECOVERY_EXHAUSTION",
        passed:
          runtime.recovery.state !==
          "EXHAUSTED",
        message:
          runtime.recovery.state ===
            "EXHAUSTED"
            ? "Encoder automatic recovery is exhausted."
            : "Encoder recovery remains available.",
      },
      {
        id:
          "ENCODER_AVAILABILITY",
        passed:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR",
        message:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR"
            ? "Encoder is available for a new start."
            : `Encoder is currently ${runtime.session.status}.`,
      },
      {
        id:
          "SCHEDULE_COUNTDOWN",
        passed:
          !countdown.scheduled ||
          countdown.secondsUntilStart == null ||
          countdown.secondsUntilStart >=
            -Math.max(
              session.startWindowLateMinutes,
              0,
            ) *
              60,
        message:
          !countdown.scheduled
            ? "No scheduled start restricts this session."
            : `Scheduled start countdown is ${String(
                countdown.secondsUntilStart,
              )} seconds.`,
      },
    ];

  return {
    gameId,
    ready:
      checks.every(
        (check) =>
          check.passed,
      ),
    checkedAt:
      new Date().toISOString(),
    checks,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/goLiveSessions.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateGameDayGoLivePreflight } from "../services/gameDayGoLivePreflight.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate go-live route imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    '"/go-live-sessions/:gameId/game-day-preflight"'
  )
) {
  const candidates = [
    '  app.get(\n    "/go-live-sessions/:gameId/audit",',
    '  app.get(\n    "/go-live-sessions/:gameId",',
  ];

  let idx = -1;

  for (const marker of candidates) {
    idx =
      text.indexOf(
        marker,
      );

    if (idx >= 0) {
      break;
    }
  }

  if (idx < 0) {
    throw new Error(
      "Unable to locate route insertion point.",
    );
  }

  const route =
`  app.get(
    "/go-live-sessions/:gameId/game-day-preflight",
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
          preflight:
            evaluateGameDayGoLivePreflight(
              gameId,
            ),
        },
      };
    },
  );

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    route +
    text.slice(
      idx,
    );
}

const armRoute =
  text.indexOf(
    '"/go-live-sessions/:gameId/arm"',
  );

if (
  armRoute >= 0 &&
  !text.slice(
    armRoute,
    armRoute + 6000,
  ).includes(
    "GAME_DAY_GO_LIVE_PREFLIGHT_21_9"
  )
) {
  const markers = [
`      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );`,
`      const preflight =
        evaluateStreamingReadiness(gameId);`,
  ];

  let idx = -1;

  for (const marker of markers) {
    idx =
      text.indexOf(
        marker,
        armRoute,
      );

    if (idx >= 0) {
      break;
    }
  }

  if (idx < 0) {
    throw new Error(
      "Unable to locate arm readiness block.",
    );
  }

  const guard =
`      // GAME_DAY_GO_LIVE_PREFLIGHT_21_9
      const gameDayPreflight =
        evaluateGameDayGoLivePreflight(
          gameId,
        );

      if (
        !gameDayPreflight.ready
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Game-day go-live preflight failed.",
          data: {
            preflight:
              gameDayPreflight,
          },
        });
      }

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    guard +
    text.slice(
      idx,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "type GameDayGoLivePreflight ="
  )
) {
  const marker =
    "type GoLiveSession = {";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx < 0) {
    throw new Error(
      "Unable to locate GoLiveSession type.",
    );
  }

  const type =
`type GameDayGoLivePreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: Array<{
    id: string;
    passed: boolean;
    message: string;
  }>;
};

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    type +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "gameDayGoLivePreflight,"
  )
) {
  const marker =
    "  const [\n    goLiveSession,";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx < 0) {
    throw new Error(
      "Unable to locate goLiveSession state.",
    );
  }

  const end =
    text.indexOf(
      ";",
      idx,
    );

  if (end < 0) {
    throw new Error(
      "Unable to locate goLiveSession state end.",
    );
  }

  const state =
`

  const [
    gameDayGoLivePreflight,
    setGameDayGoLivePreflight,
  ] =
    useState<GameDayGoLivePreflight | null>(
      null,
    );`;

  text =
    text.slice(
      0,
      end + 1,
    ) +
    state +
    text.slice(
      end + 1,
    );
}

if (
  !text.includes(
    "async function runGameDayGoLivePreflight"
  )
) {
  const candidates = [
    "  async function refreshGoLiveAudit() {",
    "  async function loadGoLiveSession() {",
    "  async function runStreamingPreflight() {",
  ];

  let idx = -1;

  for (const marker of candidates) {
    idx =
      text.indexOf(
        marker,
      );

    if (idx >= 0) {
      break;
    }
  }

  if (idx < 0) {
    throw new Error(
      "Unable to locate dashboard function insertion point.",
    );
  }

  const fn =
    '  async function runGameDayGoLivePreflight() {\n' +
    '    const normalized = gameId.trim();\n' +
    '    if (!normalized) return;\n' +
    '    setBusy(true);\n' +
    '    try {\n' +
    '      const response = await fetch(\n' +
    '        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/game-day-preflight`,\n' +
    '        { cache: "no-store" },\n' +
    '      );\n' +
    '      const json = await response.json();\n' +
    '      if (!response.ok) throw new Error(json?.error ?? "Unable to run game-day go-live preflight.");\n' +
    '      setGameDayGoLivePreflight(json?.data?.preflight ?? null);\n' +
    '      setError(null);\n' +
    '    } catch (preflightError) {\n' +
    '      setError(preflightError instanceof Error ? preflightError.message : "Unable to run game-day go-live preflight.");\n' +
    '    } finally {\n' +
    '      setBusy(false);\n' +
    '    }\n' +
    '  }\n\n';

  text =
    text.slice(
      0,
      idx,
    ) +
    fn +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "Game-Day Go-Live Preflight"
  )
) {
  const candidates = [
    "Production Go-Live",
    "Streaming Readiness",
  ];

  let base = -1;

  for (const marker of candidates) {
    base =
      text.indexOf(
        marker,
      );

    if (base >= 0) {
      break;
    }
  }

  if (base < 0) {
    throw new Error(
      "Unable to locate go-live dashboard UI.",
    );
  }

  const anchor =
    '        <div className="mt-4 flex flex-wrap gap-3">';

  let idx =
    text.indexOf(
      anchor,
      base,
    );

  if (idx < 0) {
    idx =
      text.indexOf(
        "      </div>",
        base,
      );
  }

  if (idx < 0) {
    throw new Error(
      "Unable to locate dashboard insertion point.",
    );
  }

  const ui =
`        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="text-sm font-semibold">
                Game-Day Go-Live Preflight
              </div>
              <p className="mt-1 text-xs text-slate-500">
                Final production gate combining schedule, readiness, encoder, recovery, incident, and emergency-stop status.
              </p>
            </div>

            <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
              {gameDayGoLivePreflight
                ? gameDayGoLivePreflight.ready
                  ? "READY"
                  : "BLOCKED"
                : "NOT CHECKED"}
            </span>
          </div>

          <div className="mt-3">
            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void runGameDayGoLivePreflight()
              }
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
            >
              Run Final Go-Live Preflight
            </button>
          </div>

          {gameDayGoLivePreflight && (
            <div className="mt-4 space-y-2">
              {gameDayGoLivePreflight.checks.map(
                (check) => (
                  <div
                    key={check.id}
                    className="flex items-start justify-between gap-3 rounded border border-slate-800 p-3"
                  >
                    <div>
                      <div className="text-xs font-semibold">
                        {check.id}
                      </div>
                      <div className="mt-1 text-xs text-slate-500">
                        {check.message}
                      </div>
                    </div>

                    <span className={\`text-xs font-semibold \${check.passed ? "text-slate-300" : "text-red-300"}\`}>
                      {check.passed ? "PASS" : "FAIL"}
                    </span>
                  </div>
                ),
              )}
            </div>
          )}
        </div>

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    ui +
    text.slice(
      idx,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.9 game-day go-live readiness / final operator preflight", () => {
  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/gameDayGoLivePreflight.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/goLiveSessions.ts",
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

  it("provides final production readiness service",()=> {
    expect(service).toContain("evaluateGameDayGoLivePreflight");
    expect(service).toContain('"STREAMING_PREFLIGHT"');
    expect(service).toContain('"EMERGENCY_STOP"');
    expect(service).toContain('"DEGRADED_INCIDENT"');
  });

  it("provides final preflight API",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/game-day-preflight"');
    expect(route).toContain("evaluateGameDayGoLivePreflight");
  });

  it("blocks arm when final preflight fails",()=> {
    expect(route).toContain("GAME_DAY_GO_LIVE_PREFLIGHT_21_9");
    expect(route).toContain("Game-day go-live preflight failed.");
  });

  it("provides operator final preflight UI",()=> {
    expect(panel).toContain("Game-Day Go-Live Preflight");
    expect(panel).toContain("Run Final Go-Live Preflight");
  });
});
EOF

if [[ -f "$DOC" ]] && ! grep -q "Milestone 21.9 — Game-day go-live readiness" "$DOC"; then
cat >> "$DOC" <<'EOF'

## Milestone 21.9 — Game-day go-live readiness / final operator preflight

SportsOS provides one final production go-live preflight combining streaming readiness, schedule window, go-live state, emergency-stop lock, degraded incident status, encoder recovery state, encoder availability, and schedule countdown.

Endpoint:

```text
GET /go-live-sessions/:gameId/game-day-preflight
```

Arming is blocked when this final preflight fails.
EOF
fi

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.9 preflight recovery installed"
echo "============================================================"
echo
echo "Restored:"
echo "  - missing gameDayGoLivePreflight.ts service"
echo "  - route import/endpoint if absent"
echo "  - arm guard if absent"
echo "  - dashboard type/state/action/UI if absent"
echo "  - 21.9 regression test"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rerun:"
echo "  bash sportsos-milestone-21.10-production-go-live-acceptance-closeout.sh"
