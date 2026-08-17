#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.2-pregame-readiness"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
GAME_LIB="apps/dashboard/lib/tournament-game-operations.ts"
OVERRIDE_LIB="apps/dashboard/lib/testing-override.ts"
TEST_FILE="apps/dashboard/test/tournament-game-operations-7.1.test.ts"
READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
READINESS_TEST="apps/dashboard/test/tournament-pregame-readiness-7.2.test.ts"

for file in "$WORKSPACE" "$GAME_LIB" "$OVERRIDE_LIB" "$TEST_FILE"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'TournamentGameOperationsWorkspace' "$WORKSPACE" || {
  echo "ERROR: 7.1 workspace prerequisite not found." >&2
  exit 1
}

grep -Fq 'effectiveReadiness' "$OVERRIDE_LIB" || {
  echo "ERROR: 7.1.1 testing override prerequisite not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$GAME_LIB")" \
  "$BACKUP_DIR/$(dirname "$OVERRIDE_LIB")" \
  "$BACKUP_DIR/$(dirname "$READINESS_LIB")" \
  "$BACKUP_DIR/$(dirname "$READINESS_TEST")"

for file in "$WORKSPACE" "$GAME_LIB" "$OVERRIDE_LIB" "$TEST_FILE" "$READINESS_LIB" "$READINESS_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$READINESS_LIB" <<'EOF'
import type { TournamentGameOperationsGame } from "./tournament-game-operations";

export type PregameReadinessState =
  | "PASS"
  | "WARNING"
  | "BLOCKED"
  | "UNKNOWN";

export type PregameReadinessSeverity = "required" | "recommended";

export type PregameReadinessCheck = {
  id:
    | "teams"
    | "rink"
    | "scheduledStart"
    | "rosters"
    | "scoreboard"
    | "scoringOperator"
    | "stream";
  label: string;
  state: PregameReadinessState;
  severity: PregameReadinessSeverity;
  detail: string;
  source: "game" | "future-integration";
};

export type PregameReadinessSummary = {
  checks: PregameReadinessCheck[];
  actualReady: boolean;
  actualBlockingCount: number;
  warningCount: number;
  unknownCount: number;
  effectiveReady: boolean;
  testingOverrideApplied: boolean;
};

function derivedCheck(
  id: PregameReadinessCheck["id"],
  label: string,
  value: boolean,
  detailWhenReady: string,
  detailWhenBlocked: string,
): PregameReadinessCheck {
  return {
    id,
    label,
    state: value ? "PASS" : "BLOCKED",
    severity: "required",
    detail: value ? detailWhenReady : detailWhenBlocked,
    source: "game",
  };
}

function futureCheck(
  id: PregameReadinessCheck["id"],
  label: string,
  severity: PregameReadinessSeverity,
  detail: string,
): PregameReadinessCheck {
  return {
    id,
    label,
    state: "UNKNOWN",
    severity,
    detail,
    source: "future-integration",
  };
}

export function buildPregameReadinessChecks(
  game: TournamentGameOperationsGame,
): PregameReadinessCheck[] {
  return [
    derivedCheck(
      "teams",
      "Teams assigned",
      game.readiness.teamsAssigned,
      "Home and away teams are assigned.",
      "Both home and away teams must be assigned.",
    ),
    derivedCheck(
      "rink",
      "Rink assigned",
      game.readiness.rinkAssigned,
      "A rink is assigned.",
      "A rink must be assigned before normal game start.",
    ),
    derivedCheck(
      "scheduledStart",
      "Scheduled start",
      game.readiness.scheduledStartAssigned,
      "Scheduled start time is present.",
      "Scheduled start time is missing.",
    ),
    futureCheck(
      "rosters",
      "Rosters available",
      "required",
      "Roster availability will be connected to the roster-lock workflow in Milestone 7.4.",
    ),
    futureCheck(
      "scoreboard",
      "Scoreboard connection",
      "recommended",
      "Scoreboard readiness will use device connectivity when the operations bridge is connected.",
    ),
    futureCheck(
      "scoringOperator",
      "Scoring operator",
      "required",
      "Scoring-operator assignment is not yet part of the current game record.",
    ),
    futureCheck(
      "stream",
      "Stream availability",
      "recommended",
      "Stream readiness will be connected during broadcast integration.",
    ),
  ];
}

export function summarizePregameReadiness(
  checks: PregameReadinessCheck[],
  testingOverrideEnabled: boolean,
): PregameReadinessSummary {
  const actualBlockingCount = checks.filter(
    (check) => check.severity === "required" && check.state === "BLOCKED",
  ).length;

  const warningCount = checks.filter(
    (check) => check.state === "WARNING",
  ).length;

  const unknownCount = checks.filter(
    (check) => check.state === "UNKNOWN",
  ).length;

  /*
   * UNKNOWN checks are visible but do not block until their backing
   * integration exists. This prevents 7.2 from inventing readiness facts
   * that are not yet represented by authoritative server state.
   */
  const actualReady = actualBlockingCount === 0;

  return {
    checks,
    actualReady,
    actualBlockingCount,
    warningCount,
    unknownCount,
    effectiveReady: actualReady || testingOverrideEnabled,
    testingOverrideApplied: testingOverrideEnabled && !actualReady,
  };
}

export function buildPregameReadinessSummary(
  game: TournamentGameOperationsGame,
  testingOverrideEnabled: boolean,
): PregameReadinessSummary {
  return summarizePregameReadiness(
    buildPregameReadinessChecks(game),
    testingOverrideEnabled,
  );
}
EOF

cat > "$READINESS_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  buildPregameReadinessChecks,
  buildPregameReadinessSummary,
  summarizePregameReadiness,
  type PregameReadinessCheck,
} from "../lib/tournament-pregame-readiness";
import type { TournamentGameOperationsGame } from "../lib/tournament-game-operations";

function game(
  overrides: Partial<TournamentGameOperationsGame["readiness"]> = {},
): TournamentGameOperationsGame {
  return {
    id: "game-72",
    homeTeamName: "Lakers",
    awayTeamName: "Bears",
    venueName: "Arena",
    rinkName: "Rink A",
    scheduledStart: "2026-08-16T20:00:00Z",
    status: "SCHEDULED",
    scoringStatus: "NOT_STARTED",
    readiness: {
      teamsAssigned: true,
      rinkAssigned: true,
      scheduledStartAssigned: true,
      ...overrides,
    },
  };
}

describe("Milestone 7.2 pregame readiness", () => {
  it("derives authoritative checks from current game state", () => {
    const checks = buildPregameReadinessChecks(game());

    expect(checks.find((check) => check.id === "teams")?.state).toBe("PASS");
    expect(checks.find((check) => check.id === "rink")?.state).toBe("PASS");
    expect(
      checks.find((check) => check.id === "scheduledStart")?.state,
    ).toBe("PASS");
  });

  it("blocks on missing required current game data", () => {
    const summary = buildPregameReadinessSummary(
      game({
        teamsAssigned: false,
        rinkAssigned: false,
      }),
      false,
    );

    expect(summary.actualReady).toBe(false);
    expect(summary.actualBlockingCount).toBe(2);
    expect(summary.effectiveReady).toBe(false);
  });

  it("keeps future integrations visible without pretending they are ready", () => {
    const summary = buildPregameReadinessSummary(game(), false);

    expect(summary.unknownCount).toBe(4);
    expect(
      summary.checks.filter((check) => check.source === "future-integration"),
    ).toHaveLength(4);
    expect(summary.actualReady).toBe(true);
  });

  it("testing override changes only effective readiness", () => {
    const summary = buildPregameReadinessSummary(
      game({ rinkAssigned: false }),
      true,
    );

    expect(summary.actualReady).toBe(false);
    expect(summary.effectiveReady).toBe(true);
    expect(summary.testingOverrideApplied).toBe(true);
    expect(
      summary.checks.find((check) => check.id === "rink")?.state,
    ).toBe("BLOCKED");
  });

  it("required UNKNOWN integrations do not block before integration exists", () => {
    const checks: PregameReadinessCheck[] = [
      {
        id: "scoringOperator",
        label: "Scoring operator",
        state: "UNKNOWN",
        severity: "required",
        detail: "Not integrated yet.",
        source: "future-integration",
      },
    ];

    const summary = summarizePregameReadiness(checks, false);

    expect(summary.actualBlockingCount).toBe(0);
    expect(summary.unknownCount).toBe(1);
    expect(summary.actualReady).toBe(true);
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function replaceOnce(label, search, replacement) {
  if (!text.includes(search)) {
    throw new Error(`Expected ${label} anchor not found.`);
  }
  text = text.replace(search, replacement);
}

if (!text.includes('from "../../lib/tournament-pregame-readiness";')) {
  const anchor =
`} from "../../lib/testing-override";`;

  replaceOnce(
    "testing override import",
    anchor,
`} from "../../lib/testing-override";
import {
  buildPregameReadinessSummary,
  type PregameReadinessCheck,
} from "../../lib/tournament-pregame-readiness";`,
  );
}

if (!text.includes("function ReadinessStateBadge")) {
  const anchor = `function ReadinessRow({`;

  replaceOnce(
    "ReadinessRow function",
    anchor,
`function ReadinessStateBadge({
  state,
}: {
  state: PregameReadinessCheck["state"];
}) {
  const label =
    state === "PASS"
      ? "Ready"
      : state === "BLOCKED"
        ? "Blocked"
        : state === "WARNING"
          ? "Warning"
          : "Unknown";

  const className =
    state === "PASS"
      ? "text-emerald-400"
      : state === "BLOCKED"
        ? "text-red-400"
        : state === "WARNING"
          ? "text-amber-400"
          : "text-slate-400";

  return <span className={\`text-sm font-semibold \${className}\`}>{label}</span>;
}

function PregameReadinessRow({
  check,
}: {
  check: PregameReadinessCheck;
}) {
  return (
    <div className="rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold text-slate-200">
              {check.label}
            </span>
            <span className="rounded-full border border-slate-800 px-2 py-0.5 text-[10px] uppercase tracking-wide text-slate-500">
              {check.severity}
            </span>
          </div>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            {check.detail}
          </p>
        </div>
        <ReadinessStateBadge state={check.state} />
      </div>
    </div>
  );
}

${anchor}`,
  );
}

if (!text.includes("pregameReadinessSummary")) {
  const anchor =
`  const toggleTestingOverride = () => {`;

  replaceOnce(
    "testing override toggle",
    anchor,
`  const pregameReadinessSummary = useMemo(
    () =>
      selectedGame
        ? buildPregameReadinessSummary(
            selectedGame,
            testingOverrideEnabled,
          )
        : null,
    [selectedGame, testingOverrideEnabled],
  );

${anchor}`,
  );
}

const oldAsideStart =
`            <aside className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
              <div className="flex items-center justify-between gap-3">
                <h2 className="font-semibold text-slate-100">
                  Readiness summary
                </h2>`;

if (text.includes(oldAsideStart)) {
  text = text.replace(
    oldAsideStart,
`            <aside className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Pregame readiness
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Actual vs effective readiness
                  </p>
                </div>`,
  );
}

const oldCount =
`                  {effectiveReadinessCount?.passed}/{effectiveReadinessCount?.total}`;

if (text.includes(oldCount)) {
  text = text.replace(
    oldCount,
`                  {pregameReadinessSummary?.effectiveReady ? "READY" : "BLOCKED"}`,
  );
}

const readinessBlockRegex = /              <div className="mt-4 space-y-2">[\s\S]*?              <\/div>\n\n              <p className="mt-4 text-xs leading-5 text-slate-500">/;

const match = text.match(readinessBlockRegex);

if (!match) {
  throw new Error("Expected readiness block was not found.");
}

const replacement =
`              <div className="mt-4 space-y-2">
                {pregameReadinessSummary?.checks.map((check) => (
                  <PregameReadinessRow key={check.id} check={check} />
                ))}
              </div>

              <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
                <div className="rounded-lg border border-slate-800 px-3 py-2">
                  <span className="text-slate-500">Actual</span>
                  <div
                    data-testid="pregame-actual-readiness"
                    className={
                      pregameReadinessSummary?.actualReady
                        ? "mt-1 font-semibold text-emerald-400"
                        : "mt-1 font-semibold text-red-400"
                    }
                  >
                    {pregameReadinessSummary?.actualReady
                      ? "READY"
                      : "BLOCKED"}
                  </div>
                </div>

                <div className="rounded-lg border border-slate-800 px-3 py-2">
                  <span className="text-slate-500">Effective</span>
                  <div
                    data-testid="pregame-effective-readiness"
                    className={
                      pregameReadinessSummary?.effectiveReady
                        ? "mt-1 font-semibold text-emerald-400"
                        : "mt-1 font-semibold text-red-400"
                    }
                  >
                    {pregameReadinessSummary?.effectiveReady
                      ? "READY"
                      : "BLOCKED"}
                  </div>
                </div>
              </div>

              {pregameReadinessSummary?.testingOverrideApplied ? (
                <p
                  data-testid="pregame-testing-override-applied"
                  className="mt-3 rounded-lg border border-amber-800/60 bg-amber-950/20 px-3 py-2 text-xs font-semibold text-amber-300"
                >
                  Testing override is bypassing one or more required readiness
                  failures. Actual readiness remains BLOCKED.
                </p>
              ) : null}

              <p className="mt-4 text-xs leading-5 text-slate-500">`;

text = text.replace(readinessBlockRegex, replacement);

text = text.replace(
`                Actual stored game data is never changed by testing override.
                Future Milestone 7 readiness gates can consume this shared
                helper so incomplete setup may be bypassed during development.`,
`                Unknown checks remain visible but non-blocking until their
                authoritative integrations exist. Testing override changes only
                effective readiness; it never changes actual readiness or stored
                game data.`,
);

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - formal PregameReadinessCheck model"
echo "  - PASS / WARNING / BLOCKED / UNKNOWN states"
echo "  - required vs recommended checks"
echo "  - authoritative checks for teams/rink/scheduled start"
echo "  - visible UNKNOWN placeholders for:"
echo "      rosters"
echo "      scoreboard connection"
echo "      scoring operator"
echo "      stream availability"
echo "  - actual readiness"
echo "  - effective readiness"
echo "  - testing override bypass indicator"
echo "  - automated 7.2 readiness tests"
echo
echo "Important design rule:"
echo "  UNKNOWN future integrations do NOT silently become PASS."
echo "  They are visible and non-blocking until an authoritative data source"
echo "  is connected in the milestone that owns that integration."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo
echo "  npm run build && \\"
echo "  docker compose up -d --build dashboard && \\"
echo "  npm run test:e2e:docker"
