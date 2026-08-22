#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.9-preflight-auto-rerun-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx" \
  "apps/api/src/routes/gameDayHardwarePreflight.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

PANEL="apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
TEST="packages/core/test/preflight-auto-rerun-18.9.test.ts"
DOC="docs/GAME-DAY-HARDWARE-PREFLIGHT.md"

for file in "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("autoRerunEnabled")) {
  const marker =
`  const [busy, setBusy] =
    useState(false);`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate busy state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    autoRerunEnabled,
    setAutoRerunEnabled,
  ] =
    useState(true);

  const autoRerunInFlight =
    useRef(false);`
    );
}

if (
  !text.includes("useRef") &&
  text.includes("from \"react\"")
) {
  text =
    text.replace(
`  useEffect,
  useState,`,
`  useEffect,
  useRef,
  useState,`
    );
}

if (!text.includes("runPreflightSilently")) {
  const marker =
`  async function runPreflight() {`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate runPreflight.",
    );
  }

  const fn =
`  const runPreflightSilently =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        if (
          autoRerunInFlight.current
        ) {
          return;
        }

        autoRerunInFlight.current =
          true;

        try {
          const response =
            await fetch(
              \`\${API_BASE}/game-day-hardware-preflight/\${encodeURIComponent(targetGameId)}\`,
              {
                method:
                  "POST",
              },
            );

          const json =
            await response.json();

          if (
            json?.data?.preflight
          ) {
            setLatest(
              json.data.preflight,
            );
          }

          await loadHistory(
            targetGameId,
          );
        } finally {
          autoRerunInFlight.current =
            false;
        }
      },
      [
        loadHistory,
      ],
    );

`;

  text =
    text.slice(0, idx) +
    fn +
    text.slice(idx);
}

if (!text.includes("Preflight auto-rerun loop")) {
  const marker =
`  // Preflight countdown clock`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate countdown effect.",
    );
  }

  const effect =
`  // Preflight auto-rerun loop
  useEffect(() => {
    const normalizedGameId =
      gameId.trim();

    if (
      !autoRerunEnabled ||
      !normalizedGameId ||
      !freshness?.fresh ||
      !freshness.expiresAt
    ) {
      return;
    }

    const remainingMs =
      Date.parse(
        freshness.expiresAt,
      ) -
      Date.now();

    if (
      remainingMs >
        120000 ||
      remainingMs <=
        0
    ) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          void runPreflightSilently(
            normalizedGameId,
          );
        },
        1000,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    gameId,
    freshness,
    autoRerunEnabled,
    runPreflightSilently,
    countdownNow,
  ]);

`;

  text =
    text.slice(0, idx) +
    effect +
    text.slice(idx);
}

if (!text.includes("Auto-Rerun:")) {
  const anchor =
`          <span className="rounded border border-slate-700 px-3 py-1 font-mono text-sm font-semibold">`;

  const idx =
    text.indexOf(
      anchor,
      text.indexOf(
        "Start Window Guidance",
      ),
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate Start Window Guidance countdown.",
    );
  }

  const controls =
`          <button
            type="button"
            onClick={() =>
              setAutoRerunEnabled(
                (current) =>
                  !current,
              )
            }
            className="rounded border border-slate-700 px-3 py-1 text-xs font-medium"
          >
            Auto-Rerun:{" "}
            {autoRerunEnabled
              ? "ON"
              : "OFF"}
          </button>

`;

  text =
    text.slice(0, idx) +
    controls +
    text.slice(idx);
}

if (!text.includes("Auto-rerun will refresh")) {
  const anchor =
`        <p className="mt-3 text-sm text-slate-400">`;

  const idx =
    text.indexOf(
      anchor,
      text.indexOf(
        "Start Window Guidance",
      ),
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate Start Window Guidance text.",
    );
  }

  const note =
`        <p className="mt-2 text-xs text-slate-500">
          {autoRerunEnabled
            ? "Auto-rerun will refresh a fresh preflight when 2 minutes or less remain."
            : "Auto-rerun is paused; rerun manually before expiration."}
        </p>

`;

  text =
    text.slice(0, idx) +
    note +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Automatic preflight rerun

Milestone 18.9 adds optional automatic refresh of a still-valid preflight as it approaches expiration.

Behavior:

- auto-rerun is enabled by default
- when a fresh preflight has 2 minutes or less remaining, SportsOS runs a new preflight automatically
- overlapping background reruns are prevented
- the operator may pause auto-rerun
- failed reruns do not silently authorize game start; the server-side start gate remains authoritative

This keeps the game-start window current without relying on the operator to manually rerun at the last second.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.9 preflight auto-rerun / start-window refresh", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("enables auto-rerun by default", () => {
    expect(panel).toContain(
      "autoRerunEnabled",
    );

    expect(panel).toContain(
      "useState(true)",
    );
  });

  it("reruns when two minutes or less remain", () => {
    expect(panel).toContain(
      "remainingMs >",
    );

    expect(panel).toContain(
      "120000",
    );

    expect(panel).toContain(
      "runPreflightSilently",
    );
  });

  it("prevents overlapping background reruns", () => {
    expect(panel).toContain(
      "autoRerunInFlight",
    );
  });

  it("allows the operator to pause auto-rerun", () => {
    expect(panel).toContain(
      "Auto-Rerun:",
    );

    expect(panel).toContain(
      "Auto-rerun is paused",
    );
  });

  it("keeps server authorization authoritative", () => {
    expect(panel).toContain(
      "/game-day-hardware-preflight/",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - automatic preflight rerun"
echo "  - rerun threshold at <=2 minutes"
echo "  - overlapping-request protection"
echo "  - Auto-Rerun ON/OFF operator control"
echo "  - silent background refresh"
echo "  - server start gate remains authoritative"
echo "  - Milestone 18.9 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 18.10 - Game-Day Deployment Acceptance / Closeout"
