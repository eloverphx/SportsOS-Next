#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.2-game-day-preflight-dashboard-${STAMP}"

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
  "apps/api/src/routes/gameDayHardwarePreflight.ts" \
  "apps/api/src/services/gameDayHardwarePreflight.ts" \
  "apps/dashboard/app/scoreboards/operations/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

PANEL="apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
TEST="packages/core/test/game-day-preflight-dashboard-18.2.test.ts"

for file in "$PANEL" "$PAGE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PANEL")" "$(dirname "$TEST")"

cat > "$PANEL" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useState,
} from "react";

type PreflightCheck = {
  id:
    | "COMMISSIONING"
    | "HEARTBEAT"
    | "RELIABILITY"
    | "SELF_TEST";
  passed: boolean;
  detail: string;
};

type GameDayHardwarePreflight = {
  preflightId: string;
  gameId: string;
  deviceId: string;
  status:
    | "PASS"
    | "FAIL";
  checks: PreflightCheck[];
  startedAt: string;
  completedAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function GameDayHardwarePreflightPanel() {
  const [gameId, setGameId] =
    useState("");

  const [latest, setLatest] =
    useState<GameDayHardwarePreflight | null>(
      null,
    );

  const [history, setHistory] =
    useState<GameDayHardwarePreflight[]>(
      [],
    );

  const [busy, setBusy] =
    useState(false);

  const [error, setError] =
    useState<string | null>(
      null,
    );

  const loadHistory =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setLatest(
            null,
          );
          setHistory(
            [],
          );
          return;
        }

        const [
          latestResponse,
          historyResponse,
        ] =
          await Promise.all([
            fetch(
              `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(normalized)}/latest`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(normalized)}/history`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);

        if (
          latestResponse.ok
        ) {
          const json =
            await latestResponse.json();

          setLatest(
            json?.data?.preflight ??
            null,
          );
        }

        if (
          historyResponse.ok
        ) {
          const json =
            await historyResponse.json();

          setHistory(
            json?.data?.preflights ??
            [],
          );
        }
      },
      [],
    );

  async function runPreflight() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before running preflight.",
      );
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(normalized)}`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      const result =
        json?.data?.preflight ??
        null;

      if (result) {
        setLatest(
          result,
        );
      }

      if (!response.ok) {
        setError(
          json?.error ??
          `Preflight failed (${response.status}).`,
        );
      } else {
        setError(
          null,
        );
      }

      await loadHistory(
        normalized,
      );
    } catch (runError) {
      setError(
        runError instanceof Error
          ? runError.message
          : "Unable to run game-day hardware preflight.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  useEffect(() => {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          void loadHistory(
            normalized,
          );
        },
        400,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    gameId,
    loadHistory,
  ]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Game-Day Hardware Preflight
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Run a fresh scoreboard readiness check for the selected game before start.
          </p>
        </div>

        {latest && (
          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-semibold">
            {latest.status}
          </span>
        )}
      </div>

      <div className="mt-5 flex flex-col gap-3 sm:flex-row">
        <input
          value={gameId}
          onChange={(event) =>
            setGameId(
              event.target.value,
            )
          }
          placeholder="Game ID"
          className="min-w-0 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
        />

        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void runPreflight()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Run Game-Day Preflight
        </button>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      {latest && (
        <div className="mt-5 rounded-xl border border-slate-800 p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="font-semibold">
                Latest Preflight
              </div>
              <div className="mt-1 text-xs text-slate-500">
                Device{" "}
                <span className="font-mono">
                  {latest.deviceId}
                </span>
              </div>
            </div>

            <div className="text-xs text-slate-500">
              {latest.completedAt}
            </div>
          </div>

          <div className="mt-4 grid gap-3 md:grid-cols-2">
            {latest.checks.map(
              (check) => (
                <div
                  key={check.id}
                  className="rounded-lg border border-slate-800 p-3"
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-sm font-semibold">
                      {check.id}
                    </span>
                    <span className="rounded border border-slate-700 px-2 py-1 text-xs">
                      {check.passed
                        ? "PASS"
                        : "FAIL"}
                    </span>
                  </div>

                  <p className="mt-2 text-xs text-slate-500">
                    {check.detail}
                  </p>
                </div>
              ),
            )}
          </div>
        </div>
      )}

      {history.length > 0 && (
        <div className="mt-5 rounded-xl border border-slate-800 p-4">
          <div className="font-semibold">
            Preflight History
          </div>

          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">
                    Completed
                  </th>
                  <th className="pb-2 pr-4">
                    Device
                  </th>
                  <th className="pb-2 pr-4">
                    Result
                  </th>
                  <th className="pb-2">
                    Checks
                  </th>
                </tr>
              </thead>
              <tbody>
                {history.map(
                  (item) => (
                    <tr
                      key={item.preflightId}
                      className="border-t border-slate-800"
                    >
                      <td className="py-3 pr-4 text-xs text-slate-400">
                        {item.completedAt}
                      </td>
                      <td className="py-3 pr-4 font-mono text-xs">
                        {item.deviceId}
                      </td>
                      <td className="py-3 pr-4">
                        {item.status}
                      </td>
                      <td className="py-3 text-xs text-slate-400">
                        {item.checks.filter(
                          (check) =>
                            check.passed,
                        ).length}
                        /
                        {item.checks.length}
                        {" "}passed
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { GameDayHardwarePreflightPanel } from "./GameDayHardwarePreflightPanel";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard operations imports.",
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
    "<GameDayHardwarePreflightPanel />",
  )
) {
  const commissioning =
    "<ScoreboardCommissioningWizard />";

  if (
    text.includes(
      commissioning,
    )
  ) {
    text =
      text.replace(
        commissioning,
        `${commissioning}
      <GameDayHardwarePreflightPanel />`,
      );
  } else {
    const close =
      text.lastIndexOf(
        "</main>",
      );

    if (close === -1) {
      throw new Error(
        "Unable to locate scoreboard operations insertion point.",
      );
    }

    text =
      text.slice(
        0,
        close,
      ) +
      "      <GameDayHardwarePreflightPanel />\n" +
      text.slice(
        close,
      );
  }
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.2 game-day preflight dashboard / operator workflow", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("runs preflight by game ID", () => {
    expect(panel).toContain(
      "Run Game-Day Preflight",
    );

    expect(panel).toContain(
      "/game-day-hardware-preflight/",
    );
  });

  it("shows all preflight checks", () => {
    for (const check of [
      "COMMISSIONING",
      "HEARTBEAT",
      "RELIABILITY",
      "SELF_TEST",
    ]) {
      expect(panel).toContain(
        check,
      );
    }
  });

  it("surfaces pass/fail and failure detail", () => {
    expect(panel).toContain(
      '"PASS"',
    );

    expect(panel).toContain(
      '"FAIL"',
    );

    expect(panel).toContain(
      "check.detail",
    );
  });

  it("loads latest preflight and history", () => {
    expect(panel).toContain(
      "/latest",
    );

    expect(panel).toContain(
      "/history",
    );

    expect(panel).toContain(
      "Preflight History",
    );
  });

  it("renders on scoreboard operations", () => {
    expect(page).toContain(
      "GameDayHardwarePreflightPanel",
    );

    expect(page).toContain(
      "<GameDayHardwarePreflightPanel />",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Game-Day Hardware Preflight operator panel"
echo "  - game-ID preflight execution"
echo "  - latest PASS / FAIL status"
echo "  - commissioning / heartbeat / reliability / self-test cards"
echo "  - failure detail display"
echo "  - preflight history"
echo "  - operations page integration"
echo "  - Milestone 18.2 regression tests"
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
echo "  Milestone 18.3 - Preflight Freshness Window / Expiration"
