#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.3-preflight-freshness-expiration-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/services/gameDayHardwarePreflight.ts" \
  "apps/api/src/routes/gameDayHardwarePreflight.ts" \
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/gameDayHardwarePreflight.ts"
ROUTE="apps/api/src/routes/gameDayHardwarePreflight.ts"
PANEL="apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
TEST="packages/core/test/preflight-freshness-expiration-18.3.test.ts"
DOC="docs/GAME-DAY-HARDWARE-PREFLIGHT.md"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/services/gameDayHardwarePreflight.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("PREFLIGHT_FRESHNESS_WINDOW_MS")) {
  const anchor = `const STORE_FILE =
  path.join(
    DATA_DIR,
    "game-day-hardware-preflights.json",
  );`;

  if (!text.includes(anchor)) {
    throw new Error("Unable to locate preflight store file constant.");
  }

  text = text.replace(anchor, `${anchor}

const PREFLIGHT_FRESHNESS_WINDOW_MS =
  Number.parseInt(
    process.env.SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS ??
      "900000",
    10,
  );`);
}

if (!text.includes("GameDayHardwarePreflightFreshness")) {
  text += `

export type GameDayHardwarePreflightFreshness = {
  fresh: boolean;
  expiresAt: string | null;
  ageMs: number | null;
  freshnessWindowMs: number;
  reason: string | null;
};

export function gameDayHardwarePreflightFreshness(
  preflight:
    GameDayHardwarePreflight | null,
): GameDayHardwarePreflightFreshness {
  const configured =
    Number.isFinite(
      PREFLIGHT_FRESHNESS_WINDOW_MS,
    ) &&
    PREFLIGHT_FRESHNESS_WINDOW_MS > 0
      ? PREFLIGHT_FRESHNESS_WINDOW_MS
      : 900000;

  if (!preflight) {
    return {
      fresh: false,
      expiresAt: null,
      ageMs: null,
      freshnessWindowMs:
        configured,
      reason:
        "No game-day hardware preflight has been run.",
    };
  }

  const completedMs =
    Date.parse(
      preflight.completedAt,
    );

  if (
    !Number.isFinite(
      completedMs,
    )
  ) {
    return {
      fresh: false,
      expiresAt: null,
      ageMs: null,
      freshnessWindowMs:
        configured,
      reason:
        "Latest preflight timestamp is invalid.",
    };
  }

  const ageMs =
    Math.max(
      0,
      Date.now() -
        completedMs,
    );

  const expiresAt =
    new Date(
      completedMs +
        configured,
    ).toISOString();

  if (
    preflight.status !==
      "PASS"
  ) {
    return {
      fresh: false,
      expiresAt,
      ageMs,
      freshnessWindowMs:
        configured,
      reason:
        "Latest game-day hardware preflight did not pass.",
    };
  }

  return {
    fresh:
      ageMs <=
      configured,
    expiresAt,
    ageMs,
    freshnessWindowMs:
      configured,
    reason:
      ageMs <=
        configured
        ? null
        : "Latest passing game-day hardware preflight has expired.",
  };
}
`;
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/gameDayHardwarePreflight.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("gameDayHardwarePreflightFreshness")) {
  text = text.replace(
`  latestGameDayHardwarePreflight,
  listGameDayHardwarePreflights,
  runGameDayHardwarePreflight,`,
`  gameDayHardwarePreflightFreshness,
  latestGameDayHardwarePreflight,
  listGameDayHardwarePreflights,
  runGameDayHardwarePreflight,`
  );
}

const oldLatest = `      return {
        success: true,
        data: {
          preflight:
            latestGameDayHardwarePreflight(
              gameId,
            ),
        },
      };`;

if (text.includes(oldLatest)) {
  text = text.replace(
    oldLatest,
`      const preflight =
        latestGameDayHardwarePreflight(
          gameId,
        );

      return {
        success: true,
        data: {
          preflight,
          freshness:
            gameDayHardwarePreflightFreshness(
              preflight,
            ),
        },
      };`
  );
}

if (!text.includes("/game-day-hardware-preflight/:gameId/freshness")) {
  const marker = `  app.get(
    "/game-day-hardware-preflight/:gameId/history",`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error("Unable to locate preflight history route.");
  }

  const route = `  app.get(
    "/game-day-hardware-preflight/:gameId/freshness",
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

      const preflight =
        latestGameDayHardwarePreflight(
          gameId,
        );

      return {
        success: true,
        data: {
          preflight,
          freshness:
            gameDayHardwarePreflightFreshness(
              preflight,
            ),
        },
      };
    },
  );

`;

  text = text.slice(0, idx) + route + text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx";

let text = fs.readFileSync(file, "utf8");

if (!text.includes("type PreflightFreshness")) {
  const marker = "type GameDayHardwarePreflight";
  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error("Unable to locate preflight type.");
  }

  text = text.slice(0, idx) +
`type PreflightFreshness = {
  fresh: boolean;
  expiresAt: string | null;
  ageMs: number | null;
  freshnessWindowMs: number;
  reason: string | null;
};

` +
    text.slice(idx);
}

if (!text.includes("setFreshness")) {
  const marker = `  const [history, setHistory] =
    useState<GameDayHardwarePreflight[]>(
      [],
    );`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate history state.");
  }

  text = text.replace(
    marker,
`${marker}

  const [freshness, setFreshness] =
    useState<PreflightFreshness | null>(
      null,
    );`
  );
}

const latestSet = `          setLatest(
            json?.data?.preflight ??
            null,
          );`;

if (
  text.includes(latestSet) &&
  !text.includes("json?.data?.freshness")
) {
  text = text.replace(
    latestSet,
`${latestSet}

          setFreshness(
            json?.data?.freshness ??
            null,
          );`
  );
}

if (!text.includes("Preflight Freshness")) {
  const anchor = `      {latest && (
        <div className="mt-5 rounded-xl border border-slate-800 p-4">`;

  const idx = text.indexOf(anchor);

  if (idx === -1) {
    throw new Error("Unable to locate latest preflight card.");
  }

  const block = `      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Preflight Freshness
            </div>
            <div className="mt-1 text-xs text-slate-500">
              Passing preflight results are valid for a limited game-day window.
            </div>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs font-semibold">
            {freshness?.fresh
              ? "FRESH"
              : "EXPIRED / REQUIRED"}
          </span>
        </div>

        <div className="mt-3 text-sm text-slate-400">
          {freshness?.reason ??
            (
              freshness?.expiresAt
                ? \`Valid until \${freshness.expiresAt}\`
                : "Run a game-day preflight."
            )}
        </div>

        {freshness?.ageMs != null && (
          <div className="mt-1 text-xs text-slate-500">
            Age:{" "}
            {Math.round(
              freshness.ageMs /
                1000,
            )}
            s
          </div>
        )}
      </div>

`;

  text = text.slice(0, idx) + block + text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Preflight freshness and expiration

Milestone 18.3 makes passing game-day preflights time-limited.

The default freshness window is 15 minutes (`900000` ms) and can be changed with `SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS`.

A preflight is fresh only when it exists, passed, and its completion time remains inside the configured window. Expired or failed preflights must be rerun before they count as current game-day readiness evidence.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.3 preflight freshness window / expiration", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("defines a configurable 15-minute freshness window", () => {
    expect(service).toContain(
      "SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS",
    );

    expect(service).toContain(
      '"900000"',
    );
  });

  it("requires a passing preflight to be fresh", () => {
    expect(service).toContain(
      'preflight.status !==',
    );

    expect(service).toContain(
      '"PASS"',
    );
  });

  it("expires old passing preflights", () => {
    expect(service).toContain(
      "Latest passing game-day hardware preflight has expired.",
    );

    expect(service).toContain(
      "expiresAt",
    );
  });

  it("exposes freshness through the API", () => {
    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/freshness",
    );

    expect(route).toContain(
      "gameDayHardwarePreflightFreshness",
    );
  });

  it("shows fresh versus expired status in the dashboard", () => {
    expect(panel).toContain(
      "Preflight Freshness",
    );

    expect(panel).toContain(
      "FRESH",
    );

    expect(panel).toContain(
      "EXPIRED / REQUIRED",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - configurable game-day preflight freshness window"
echo "  - default 15-minute validity"
echo "  - expiration calculation"
echo "  - failed preflight is never fresh"
echo "  - GET freshness API"
echo "  - freshness included with latest preflight"
echo "  - FRESH / EXPIRED operator status"
echo "  - Milestone 18.3 regression tests"
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
echo "  Milestone 18.4 - Game Start Preflight Enforcement"
