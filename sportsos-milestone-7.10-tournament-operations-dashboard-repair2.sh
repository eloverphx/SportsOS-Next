#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.10-tournament-operations-dashboard-repair2"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

PAGE="apps/dashboard/app/tournament/game-operations/page.tsx"
WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
SUMMARY_LIB="apps/dashboard/lib/tournament-operations-dashboard.ts"
SUMMARY_TEST="apps/dashboard/test/tournament-operations-dashboard-7.10.test.ts"
LIVE_CONTROL="apps/dashboard/components/tournament/GameLiveTransitionControl.tsx"
FINAL_CONTROL="apps/dashboard/components/tournament/GameResultFinalizationControl.tsx"

for file in \
  "$PAGE" \
  "$WORKSPACE" \
  "$LIVE_CONTROL" \
  "$FINAL_CONTROL"
do
  [[ -f "$file" ]] || {
    echo "ERROR: required file missing: $file" >&2
    exit 1
  }
done

grep -Fq 'data-testid="team-check-in-panel"' "$WORKSPACE" || {
  echo "ERROR: Team Check-In panel not found." >&2
  exit 1
}

grep -Fq 'data-testid="roster-lock-panel"' "$WORKSPACE" || {
  echo "ERROR: Roster Lock panel not found." >&2
  exit 1
}

grep -Fq 'data-testid="officials-assignment-panel"' "$WORKSPACE" || {
  echo "ERROR: Officials Assignment panel not found." >&2
  exit 1
}

grep -Fq 'data-testid="game-start-authorization-panel"' "$WORKSPACE" || {
  echo "ERROR: Game Start Authorization panel not found." >&2
  exit 1
}

grep -Fq 'data-testid="live-game-transition-panel"' "$LIVE_CONTROL" || {
  echo "ERROR: Live Game Transition control not found." >&2
  exit 1
}

grep -Fq 'data-testid="game-result-finalization-panel"' "$FINAL_CONTROL" || {
  echo "ERROR: Game Result Finalization control not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$SUMMARY_LIB")" \
  "$BACKUP_DIR/$(dirname "$SUMMARY_TEST")"

for file in "$PAGE" "$WORKSPACE" "$SUMMARY_LIB" "$SUMMARY_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$SUMMARY_LIB" <<'EOF'
export type TournamentOperationsStage =
  | "PREGAME"
  | "AUTHORIZED"
  | "LIVE"
  | "FINAL";

export type TournamentOperationsSummaryInput = {
  actualReady: boolean;
  effectiveReady: boolean;
  homeCheckedIn: boolean;
  awayCheckedIn: boolean;
  homeRosterLocked: boolean;
  awayRosterLocked: boolean;
  officialsReady: boolean;
  startAuthorized: boolean;
  liveStarted: boolean;
  finalized: boolean;
};

export type TournamentOperationsSummary = {
  stage: TournamentOperationsStage;
  completedSteps: number;
  totalSteps: number;
  completionPercent: number;
  blockers: string[];
};

export function buildTournamentOperationsSummary(
  input: TournamentOperationsSummaryInput,
): TournamentOperationsSummary {
  const steps = [
    input.homeCheckedIn,
    input.awayCheckedIn,
    input.homeRosterLocked,
    input.awayRosterLocked,
    input.officialsReady,
    input.startAuthorized,
    input.liveStarted,
    input.finalized,
  ];

  const completedSteps = steps.filter(Boolean).length;
  const totalSteps = steps.length;
  const completionPercent = Math.round(
    (completedSteps / totalSteps) * 100,
  );

  const blockers: string[] = [];

  if (!input.homeCheckedIn) blockers.push("Home team not checked in");
  if (!input.awayCheckedIn) blockers.push("Away team not checked in");
  if (!input.homeRosterLocked) blockers.push("Home roster not locked");
  if (!input.awayRosterLocked) blockers.push("Away roster not locked");
  if (!input.officialsReady) blockers.push("Required officials not assigned");

  if (!input.effectiveReady) {
    blockers.push("Pregame readiness is blocked");
  }

  if (input.finalized) {
    return {
      stage: "FINAL",
      completedSteps,
      totalSteps,
      completionPercent,
      blockers: [],
    };
  }

  if (input.liveStarted) {
    return {
      stage: "LIVE",
      completedSteps,
      totalSteps,
      completionPercent,
      blockers: [],
    };
  }

  if (input.startAuthorized) {
    return {
      stage: "AUTHORIZED",
      completedSteps,
      totalSteps,
      completionPercent,
      blockers,
    };
  }

  return {
    stage: "PREGAME",
    completedSteps,
    totalSteps,
    completionPercent,
    blockers,
  };
}
EOF

cat > "$SUMMARY_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  buildTournamentOperationsSummary,
} from "../lib/tournament-operations-dashboard";

describe("Milestone 7.10 tournament operations dashboard", () => {
  it("reports pregame blockers", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: false,
      effectiveReady: false,
      homeCheckedIn: false,
      awayCheckedIn: true,
      homeRosterLocked: false,
      awayRosterLocked: true,
      officialsReady: false,
      startAuthorized: false,
      liveStarted: false,
      finalized: false,
    });

    expect(summary.stage).toBe("PREGAME");
    expect(summary.blockers).toContain("Home team not checked in");
    expect(summary.blockers).toContain("Home roster not locked");
    expect(summary.blockers).toContain(
      "Required officials not assigned",
    );
  });

  it("reports authorized stage before live start", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: true,
      effectiveReady: true,
      homeCheckedIn: true,
      awayCheckedIn: true,
      homeRosterLocked: true,
      awayRosterLocked: true,
      officialsReady: true,
      startAuthorized: true,
      liveStarted: false,
      finalized: false,
    });

    expect(summary.stage).toBe("AUTHORIZED");
  });

  it("reports live stage", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: true,
      effectiveReady: true,
      homeCheckedIn: true,
      awayCheckedIn: true,
      homeRosterLocked: true,
      awayRosterLocked: true,
      officialsReady: true,
      startAuthorized: true,
      liveStarted: true,
      finalized: false,
    });

    expect(summary.stage).toBe("LIVE");
  });

  it("reports final stage with no blockers", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: true,
      effectiveReady: true,
      homeCheckedIn: true,
      awayCheckedIn: true,
      homeRosterLocked: true,
      awayRosterLocked: true,
      officialsReady: true,
      startAuthorized: true,
      liveStarted: true,
      finalized: true,
    });

    expect(summary.stage).toBe("FINAL");
    expect(summary.blockers).toEqual([]);
    expect(summary.completionPercent).toBe(100);
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function requireFound(condition, message) {
  if (!condition) throw new Error(message);
}

if (!text.includes('from "../../lib/tournament-operations-dashboard";')) {
  const importCandidates = [
    'import { GameResultFinalizationControl } from "./GameResultFinalizationControl";',
    'import { GameLiveTransitionControl } from "./GameLiveTransitionControl";',
  ];

  const anchor = importCandidates.find((candidate) =>
    text.includes(candidate),
  );

  requireFound(
    anchor,
    "Could not locate a stable tournament operations import anchor.",
  );

  text = text.replace(
    anchor,
`${anchor}
import {
  buildTournamentOperationsSummary,
} from "../../lib/tournament-operations-dashboard";`,
  );
}

if (!text.includes("const tournamentOperationsSummary = useMemo(")) {
  const memoIndex = text.indexOf(
    "const pregameReadinessSummary = useMemo("
  );

  requireFound(
    memoIndex >= 0,
    "Could not locate pregameReadinessSummary.",
  );

  const nextFunctionCandidates = [
    "const updateTeamCheckIn",
    "const updateRosterLock",
    "const updateOfficialAssignment",
    "const authorizeGameStart",
    "const toggleTestingOverride",
  ]
    .map((value) => ({
      value,
      index: text.indexOf(value, memoIndex),
    }))
    .filter((entry) => entry.index > memoIndex)
    .sort((a, b) => a.index - b.index);

  requireFound(
    nextFunctionCandidates.length > 0,
    "Could not locate function following readiness memo.",
  );

  const insertionPoint = nextFunctionCandidates[0].index;

  const summary = `  const tournamentOperationsSummary = useMemo(() => {
    if (!pregameReadinessSummary) {
      return null;
    }

    return buildTournamentOperationsSummary({
      actualReady: pregameReadinessSummary.actualReady,
      effectiveReady: pregameReadinessSummary.effectiveReady,
      homeCheckedIn: teamCheckInState.home,
      awayCheckedIn: teamCheckInState.away,
      homeRosterLocked: rosterLockState.home,
      awayRosterLocked: rosterLockState.away,
      officialsReady: hasRequiredOfficials(officialsAssignment),
      startAuthorized: Boolean(gameStartAuthorization),
      liveStarted: false,
      finalized: false,
    });
  }, [
    gameStartAuthorization,
    officialsAssignment,
    pregameReadinessSummary,
    rosterLockState,
    teamCheckInState,
  ]);

`;

  text =
    text.slice(0, insertionPoint) +
    summary +
    text.slice(insertionPoint);
}

if (!text.includes('data-testid="tournament-operations-overview"')) {
  const marker = 'data-testid="team-check-in-panel"';
  const markerIndex = text.indexOf(marker);

  requireFound(
    markerIndex >= 0,
    "Could not locate Team Check-In panel marker.",
  );

  const sectionStart = text.lastIndexOf("<section", markerIndex);

  requireFound(
    sectionStart >= 0,
    "Could not locate Team Check-In section opening tag.",
  );

  const overview = `            {tournamentOperationsSummary ? (
              <section
                data-testid="tournament-operations-overview"
                className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
              >
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                      Tournament operations
                    </div>
                    <h2 className="mt-1 text-xl font-bold text-slate-100">
                      {tournamentOperationsSummary.stage}
                    </h2>
                  </div>

                  <div className="text-right">
                    <div className="text-2xl font-bold text-slate-100">
                      {tournamentOperationsSummary.completionPercent}%
                    </div>
                    <div className="text-xs text-slate-500">
                      {tournamentOperationsSummary.completedSteps} /{" "}
                      {tournamentOperationsSummary.totalSteps} operational steps
                    </div>
                  </div>
                </div>

                <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
                  <div
                    className="h-full bg-slate-400 transition-all"
                    style={{
                      width: \`\${tournamentOperationsSummary.completionPercent}%\`,
                    }}
                  />
                </div>

                {tournamentOperationsSummary.blockers.length > 0 ? (
                  <div className="mt-4">
                    <div className="text-xs font-semibold uppercase tracking-wide text-amber-400">
                      Current blockers
                    </div>
                    <div className="mt-2 grid gap-2 md:grid-cols-2">
                      {tournamentOperationsSummary.blockers.map(
                        (blocker) => (
                          <div
                            key={blocker}
                            className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
                          >
                            {blocker}
                          </div>
                        ),
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="mt-4 rounded-lg border border-emerald-900/50 bg-emerald-950/20 px-3 py-2 text-xs text-emerald-300">
                    No current operational blockers.
                  </div>
                )}
              </section>
            ) : null}

`;

  text =
    text.slice(0, sectionStart) +
    overview +
    text.slice(sectionStart);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/tournament/game-operations/page.tsx";

let text = fs.readFileSync(file, "utf8");

if (!text.includes("Tournament Operations Dashboard")) {
  const heading = text.match(/<h1[^>]*>[\s\S]*?<\/h1>/m);

  if (heading) {
    text = text.replace(
      heading[0],
      heading[0].replace(
        />[\s\S]*?</,
        ">Tournament Operations Dashboard<",
      ),
    );
  }
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.10 repair 2 installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - removed brittle selected-game render regex"
echo "  - operations overview now anchors before Team Check-In"
echo "  - validates Live and Final controls in their own files"
echo
echo "Added:"
echo "  - PREGAME / AUTHORIZED / LIVE / FINAL operations stage model"
echo "  - completion percentage"
echo "  - operational blocker summary"
echo "  - Milestone 7.10 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build && \\"
echo "  docker compose up -d --build api dashboard && \\"
echo "  npm run test:e2e:docker"
