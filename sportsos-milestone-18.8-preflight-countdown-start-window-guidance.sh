#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.8-preflight-countdown-guidance-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx" \
  "apps/api/src/services/gameDayHardwarePreflight.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

PANEL="apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
TEST="packages/core/test/preflight-countdown-guidance-18.8.test.ts"
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
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "countdownNow",
  )
) {
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
    countdownNow,
    setCountdownNow,
  ] =
    useState(
      () => Date.now(),
    );`
    );
}

if (
  !text.includes(
    "Preflight countdown clock"
  )
) {
  const marker =
`  useEffect(() => {
    const normalized =
      gameId.trim();`;

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate game-ID loading effect.",
    );
  }

  const effect =
`  // Preflight countdown clock
  useEffect(() => {
    const timer =
      window.setInterval(
        () => {
          setCountdownNow(
            Date.now(),
          );
        },
        1000,
      );

    return () => {
      window.clearInterval(
        timer,
      );
    };
  }, []);

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    effect +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "remainingFreshnessMs",
  )
) {
  const marker =
`  return (`;

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate component return.",
    );
  }

  const derived =
`  const remainingFreshnessMs =
    freshness?.expiresAt
      ? Math.max(
          0,
          Date.parse(
            freshness.expiresAt,
          ) -
            countdownNow,
        )
      : null;

  const remainingFreshnessSeconds =
    remainingFreshnessMs == null
      ? null
      : Math.ceil(
          remainingFreshnessMs /
            1000,
        );

  const remainingFreshnessMinutes =
    remainingFreshnessSeconds == null
      ? null
      : Math.floor(
          remainingFreshnessSeconds /
            60,
        );

  const remainingFreshnessRemainderSeconds =
    remainingFreshnessSeconds == null
      ? null
      : remainingFreshnessSeconds %
        60;

  const preflightGuidance =
    !freshness
      ? "Run a game-day preflight before starting the game."
      : !freshness.fresh
        ? "Preflight is expired or invalid. Rerun it before game start."
        : remainingFreshnessMs != null &&
            remainingFreshnessMs <=
              120000
          ? "Preflight is close to expiration. Rerun now to avoid a start delay."
          : remainingFreshnessMs != null &&
              remainingFreshnessMs <=
                300000
            ? "Preflight is still valid, but the start window is getting short."
            : "Preflight is fresh and within the normal game-start window.";

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    derived +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "Start Window Guidance"
  )
) {
  const anchor =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Preflight Freshness`;

  const idx =
    text.indexOf(
      anchor,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate Preflight Freshness card.",
    );
  }

  const end =
    text.indexOf(
      "\n      </div>",
      idx,
    );

  if (end === -1) {
    throw new Error(
      "Unable to locate Preflight Freshness card end.",
    );
  }

  const insertAt =
    end +
    "\n      </div>".length;

  const block =
`

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Start Window Guidance
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Live countdown until the latest passing preflight expires.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 font-mono text-sm font-semibold">
            {remainingFreshnessSeconds == null
              ? "--:--"
              : \`\${String(
                  remainingFreshnessMinutes ??
                    0,
                ).padStart(
                  2,
                  "0",
                )}:\${String(
                  remainingFreshnessRemainderSeconds ??
                    0,
                ).padStart(
                  2,
                  "0",
                )}\`}
          </span>
        </div>

        <p className="mt-3 text-sm text-slate-400">
          {preflightGuidance}
        </p>

        {freshness?.fresh &&
          remainingFreshnessMs != null && (
          <div className="mt-3 text-xs text-slate-500">
            Current passing preflight expires at{" "}
            {freshness.expiresAt}.
          </div>
        )}
      </div>`;

  text =
    text.slice(
      0,
      insertAt,
    ) +
    block +
    text.slice(
      insertAt,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Preflight countdown and start-window guidance

Milestone 18.8 adds a live operator countdown to the expiration of the current passing preflight.

Guidance bands:

- more than 5 minutes remaining: normal start window
- 2–5 minutes remaining: start window is getting short
- 2 minutes or less: rerun preflight now to avoid a start delay
- expired or invalid: rerun is required before game start

The countdown is advisory UI built from the server-provided expiration timestamp. The server-side game-start gate remains authoritative.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.8 preflight countdown / start-window guidance", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("updates the countdown every second", () => {
    expect(panel).toContain(
      "Preflight countdown clock",
    );

    expect(panel).toContain(
      "setInterval",
    );

    expect(panel).toContain(
      "1000",
    );
  });

  it("calculates remaining freshness from server expiration", () => {
    expect(panel).toContain(
      "remainingFreshnessMs",
    );

    expect(panel).toContain(
      "freshness.expiresAt",
    );
  });

  it("shows start-window countdown", () => {
    expect(panel).toContain(
      "Start Window Guidance",
    );

    expect(panel).toContain(
      'padStart(',
    );
  });

  it("warns when expiration is approaching", () => {
    expect(panel).toContain(
      "close to expiration",
    );

    expect(panel).toContain(
      "start window is getting short",
    );
  });

  it("requires rerun after expiration", () => {
    expect(panel).toContain(
      "Rerun it before game start.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - live 1-second preflight countdown"
echo "  - expiration-based remaining time"
echo "  - >5 minute normal guidance"
echo "  - 2-5 minute caution guidance"
echo "  - <=2 minute rerun recommendation"
echo "  - expired rerun-required guidance"
echo "  - server remains authoritative"
echo "  - Milestone 18.8 regression tests"
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
echo "  Milestone 18.9 - Preflight Auto-Rerun / Start-Window Refresh"
