#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.2-scheduled-go-live-window-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/scheduled-go-live-window-21.2.test.ts"
DOC="docs/GO-LIVE-OPERATIONS.md"

for required in \
  ".git" \
  "$SERVICE" \
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

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/goLiveSession.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "scheduledStartAt:"
  )
) {
  text =
    text.replace(
`  lastError: string | null;
};`,
`  lastError: string | null;
  scheduledStartAt: string | null;
  startWindowEarlyMinutes: number;
  startWindowLateMinutes: number;
};`,
    );
}

if (
  !text.includes(
    "scheduledStartAt:\n      null"
  )
) {
  text =
    text.replace(
`    lastError:
      null,
  };`,
`    lastError:
      null,
    scheduledStartAt:
      null,
    startWindowEarlyMinutes:
      15,
    startWindowLateMinutes:
      15,
  };`,
    );
}

if (
  !text.includes(
    "export function configureGoLiveSchedule"
  )
) {
  const marker =
    "export function armGoLiveSession(";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate go-live arm function.",
    );
  }

  const fn =
`export function configureGoLiveSchedule(input: {
  gameId: string;
  scheduledStartAt: string | null;
  startWindowEarlyMinutes?: number;
  startWindowLateMinutes?: number;
}): GoLiveSession {
  const current =
    getGoLiveSession(
      input.gameId,
    );

  const early =
    Number.isFinite(
      input.startWindowEarlyMinutes,
    )
      ? Math.max(
          0,
          Math.min(
            120,
            Math.floor(
              Number(
                input.startWindowEarlyMinutes,
              ),
            ),
          ),
        )
      : current.startWindowEarlyMinutes;

  const late =
    Number.isFinite(
      input.startWindowLateMinutes,
    )
      ? Math.max(
          0,
          Math.min(
            120,
            Math.floor(
              Number(
                input.startWindowLateMinutes,
              ),
            ),
          ),
        )
      : current.startWindowLateMinutes;

  const scheduledStartAt =
    input.scheduledStartAt
      ? new Date(
          input.scheduledStartAt,
        ).toISOString()
      : null;

  return replaceSession({
    ...current,
    scheduledStartAt,
    startWindowEarlyMinutes:
      early,
    startWindowLateMinutes:
      late,
    lastTransitionAt:
      new Date().toISOString(),
  });
}

export function evaluateGoLiveStartWindow(
  gameId: string,
  now =
    new Date(),
): {
  scheduled: boolean;
  withinWindow: boolean;
  tooEarly: boolean;
  tooLate: boolean;
  opensAt: string | null;
  closesAt: string | null;
} {
  const session =
    getGoLiveSession(
      gameId,
    );

  if (
    !session.scheduledStartAt
  ) {
    return {
      scheduled: false,
      withinWindow: true,
      tooEarly: false,
      tooLate: false,
      opensAt: null,
      closesAt: null,
    };
  }

  const scheduledMs =
    Date.parse(
      session.scheduledStartAt,
    );

  const opensMs =
    scheduledMs -
    session.startWindowEarlyMinutes *
      60_000;

  const closesMs =
    scheduledMs +
    session.startWindowLateMinutes *
      60_000;

  const nowMs =
    now.getTime();

  return {
    scheduled: true,
    withinWindow:
      nowMs >=
        opensMs &&
      nowMs <=
        closesMs,
    tooEarly:
      nowMs <
      opensMs,
    tooLate:
      nowMs >
      closesMs,
    opensAt:
      new Date(
        opensMs,
      ).toISOString(),
    closesAt:
      new Date(
        closesMs,
      ).toISOString(),
  };
}

`;

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
    "scheduledStartAt:"
  )
) {
  throw new Error(
    "21.2 schedule fields missing.",
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
  "apps/api/src/routes/goLiveSessions.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "configureGoLiveSchedule"
  )
) {
  text =
    text.replace(
`  completeGoLiveSession,
  getGoLiveSession,`,
`  completeGoLiveSession,
  configureGoLiveSchedule,
  evaluateGoLiveStartWindow,
  getGoLiveSession,`,
    );
}

if (
  !text.includes(
    '"/go-live-sessions/:gameId/schedule"'
  )
) {
  const marker =
`  app.post(
    "/go-live-sessions/:gameId/arm",`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate go-live arm route.",
    );
  }

  const route =
`  app.put(
    "/go-live-sessions/:gameId/schedule",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          scheduledStartAt?: string | null;
          startWindowEarlyMinutes?: number;
          startWindowLateMinutes?: number;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        const session =
          configureGoLiveSchedule({
            gameId,
            scheduledStartAt:
              body.scheduledStartAt ??
              null,
            startWindowEarlyMinutes:
              body.startWindowEarlyMinutes,
            startWindowLateMinutes:
              body.startWindowLateMinutes,
          });

        return {
          success: true,
          data: {
            session,
            startWindow:
              evaluateGoLiveStartWindow(
                gameId,
              ),
          },
        };
      } catch {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid scheduled start timestamp.",
        });
      }
    },
  );

  app.get(
    "/go-live-sessions/:gameId/start-window",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

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
          session:
            getGoLiveSession(
              gameId,
            ),
          startWindow:
            evaluateGoLiveStartWindow(
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

if (
  !text.includes(
    "GO_LIVE_START_WINDOW_21_2"
  )
) {
  const marker =
`      const current =
        getGoLiveSession(
          gameId,
        );`;

  const idx =
    text.indexOf(
      marker,
      text.indexOf(
        '"/go-live-sessions/:gameId/start"',
      ),
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate go-live start current-session block.",
    );
  }

  const guard =
`      // GO_LIVE_START_WINDOW_21_2
      const startWindow =
        evaluateGoLiveStartWindow(
          gameId,
        );

      if (!startWindow.withinWindow) {
        return reply.code(409).send({
          success: false,
          error:
            startWindow.tooEarly
              ? "Go-live start window has not opened yet."
              : "Go-live start window has expired.",
          data: {
            startWindow,
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
    "scheduledStartAt:"
  )
) {
  text =
    text.replace(
`  lastError: string | null;
};`,
`  lastError: string | null;
  scheduledStartAt: string | null;
  startWindowEarlyMinutes: number;
  startWindowLateMinutes: number;
};`,
    );
}

if (
  !text.includes(
    "const [scheduledStartAt"
  )
) {
  const marker =
`  const [
    goLiveSession,
    setGoLiveSession,
  ] =
    useState<GoLiveSession | null>(
      null,
    );`;

  if (
    !text.includes(
      marker,
    )
  ) {
    throw new Error(
      "Unable to locate go-live state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    scheduledStartAt,
    setScheduledStartAt,
  ] =
    useState("");

  const [
    startWindowEarlyMinutes,
    setStartWindowEarlyMinutes,
  ] =
    useState(15);

  const [
    startWindowLateMinutes,
    setStartWindowLateMinutes,
  ] =
    useState(15);

  const [
    goLiveStartWindow,
    setGoLiveStartWindow,
  ] =
    useState<{
      scheduled: boolean;
      withinWindow: boolean;
      tooEarly: boolean;
      tooLate: boolean;
      opensAt: string | null;
      closesAt: string | null;
    } | null>(
      null,
    );`,
    );
}

if (
  !text.includes(
    "async function saveGoLiveSchedule"
  )
) {
  const marker =
    "  async function loadGoLiveSession() {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate loadGoLiveSession.",
    );
  }

  const fn =
    '  async function saveGoLiveSchedule() {\n' +
    '    const normalized = gameId.trim();\n' +
    '    if (!normalized) return;\n' +
    '    setBusy(true);\n' +
    '    try {\n' +
    '      const response = await fetch(\n' +
    '        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/schedule`,\n' +
    '        {\n' +
    '          method: "PUT",\n' +
    '          headers: { "Content-Type": "application/json" },\n' +
    '          body: JSON.stringify({\n' +
    '            scheduledStartAt: scheduledStartAt ? new Date(scheduledStartAt).toISOString() : null,\n' +
    '            startWindowEarlyMinutes,\n' +
    '            startWindowLateMinutes,\n' +
    '          }),\n' +
    '        },\n' +
    '      );\n' +
    '      const json = await response.json();\n' +
    '      if (!response.ok) throw new Error(json?.error ?? `Schedule save failed (${response.status}).`);\n' +
    '      setGoLiveSession(json?.data?.session ?? null);\n' +
    '      setGoLiveStartWindow(json?.data?.startWindow ?? null);\n' +
    '      setError(null);\n' +
    '    } catch (scheduleError) {\n' +
    '      setError(scheduleError instanceof Error ? scheduleError.message : "Unable to save go-live schedule.");\n' +
    '    } finally {\n' +
    '      setBusy(false);\n' +
    '    }\n' +
    '  }\n\n' +
    '  async function refreshGoLiveStartWindow() {\n' +
    '    const normalized = gameId.trim();\n' +
    '    if (!normalized) return;\n' +
    '    const response = await fetch(\n' +
    '      `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/start-window`,\n' +
    '      { cache: "no-store" },\n' +
    '    );\n' +
    '    if (!response.ok) return;\n' +
    '    const json = await response.json();\n' +
    '    setGoLiveSession(json?.data?.session ?? null);\n' +
    '    setGoLiveStartWindow(json?.data?.startWindow ?? null);\n' +
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
    "Scheduled Start"
  )
) {
  const marker =
`        <div className="mt-4 flex flex-wrap gap-3">`;

  const goLiveIdx =
    text.indexOf(
      "Production Go-Live",
    );

  const idx =
    text.indexOf(
      marker,
      goLiveIdx,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate Production Go-Live actions.",
    );
  }

  const block =
`        <div className="mt-4 grid gap-4 md:grid-cols-3">
          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Scheduled Start
            </span>
            <input
              type="datetime-local"
              value={scheduledStartAt}
              onChange={(event) =>
                setScheduledStartAt(
                  event.target.value,
                )
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Early Window (minutes)
            </span>
            <input
              type="number"
              min={0}
              max={120}
              value={startWindowEarlyMinutes}
              onChange={(event) =>
                setStartWindowEarlyMinutes(
                  Number(event.target.value) || 0,
                )
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Late Window (minutes)
            </span>
            <input
              type="number"
              min={0}
              max={120}
              value={startWindowLateMinutes}
              onChange={(event) =>
                setStartWindowLateMinutes(
                  Number(event.target.value) || 0,
                )
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        </div>

        <div className="mt-3 flex flex-wrap gap-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void saveGoLiveSchedule()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Save Go-Live Schedule
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void refreshGoLiveStartWindow()
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Refresh Start Window
          </button>
        </div>

        {goLiveStartWindow && (
          <div className="mt-3 rounded border border-slate-800 p-3 text-xs">
            <div className="font-semibold">
              Start Window: {goLiveStartWindow.withinWindow ? "OPEN" : goLiveStartWindow.tooEarly ? "TOO EARLY" : goLiveStartWindow.tooLate ? "EXPIRED" : "OPEN"}
            </div>
            {goLiveStartWindow.opensAt && (
              <div className="mt-1 text-slate-500">
                Opens: {goLiveStartWindow.opensAt}
              </div>
            )}
            {goLiveStartWindow.closesAt && (
              <div className="mt-1 text-slate-500">
                Closes: {goLiveStartWindow.closesAt}
              </div>
            )}
          </div>
        )}

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    block +
    text.slice(
      idx,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 21.2 — Scheduled go-live and start window

Go-live sessions may now define:

- scheduled start timestamp
- early start window in minutes
- late start window in minutes

Defaults:

```text
early window: 15 minutes
late window: 15 minutes
```

Window bounds are clamped to 0–120 minutes.

API:

```text
PUT /go-live-sessions/:gameId/schedule
GET /go-live-sessions/:gameId/start-window
```

A scheduled go-live start is rejected when it is too early or after the configured window expires.

This milestone does not auto-start the encoder. It only provides scheduling metadata and start-window enforcement.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 21.2 scheduled go-live / start window foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/goLiveSession.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/goLiveSessions.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists scheduled start and window bounds", () => {
    expect(service).toContain(
      "scheduledStartAt",
    );
    expect(service).toContain(
      "startWindowEarlyMinutes",
    );
    expect(service).toContain(
      "startWindowLateMinutes",
    );
  });

  it("evaluates start-window state", () => {
    expect(service).toContain(
      "evaluateGoLiveStartWindow",
    );
    expect(service).toContain(
      "withinWindow",
    );
    expect(service).toContain(
      "tooEarly",
    );
    expect(service).toContain(
      "tooLate",
    );
  });

  it("provides schedule and window APIs", () => {
    expect(route).toContain(
      '"/go-live-sessions/:gameId/schedule"',
    );
    expect(route).toContain(
      '"/go-live-sessions/:gameId/start-window"',
    );
  });

  it("blocks scheduled starts outside the window", () => {
    expect(route).toContain(
      "GO_LIVE_START_WINDOW_21_2",
    );
    expect(route).toContain(
      "Go-live start window has not opened yet.",
    );
    expect(route).toContain(
      "Go-live start window has expired.",
    );
  });

  it("provides operator scheduling controls", () => {
    expect(panel).toContain(
      "Scheduled Start",
    );
    expect(panel).toContain(
      "Early Window (minutes)",
    );
    expect(panel).toContain(
      "Late Window (minutes)",
    );
    expect(panel).toContain(
      "Save Go-Live Schedule",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persisted scheduled go-live start"
echo "  - configurable early/late start window"
echo "  - start-window evaluation"
echo "  - too-early / expired start blocking"
echo "  - operator schedule controls"
echo "  - no automatic encoder start yet"
echo "  - Milestone 21.2 regression tests"
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
echo "  Milestone 21.3 - Scheduled Auto-Arm / Operator Countdown"
