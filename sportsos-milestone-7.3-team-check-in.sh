#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.3-team-check-in"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
CHECKIN_LIB="apps/dashboard/lib/tournament-team-check-in.ts"
CHECKIN_TEST="apps/dashboard/test/tournament-team-check-in-7.3.test.ts"

for file in "$WORKSPACE" "$READINESS_LIB"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'buildPregameReadinessSummary' "$READINESS_LIB" || {
  echo "ERROR: Milestone 7.2 prerequisite not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$READINESS_LIB")" \
  "$BACKUP_DIR/$(dirname "$CHECKIN_LIB")" \
  "$BACKUP_DIR/$(dirname "$CHECKIN_TEST")"

for file in "$WORKSPACE" "$READINESS_LIB" "$CHECKIN_LIB" "$CHECKIN_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$CHECKIN_LIB" <<'EOF'
export const SPORTSOS_TEAM_CHECKIN_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:team-check-in";

export type TeamCheckInSide = "home" | "away";

export type TeamCheckInState = {
  home: boolean;
  away: boolean;
};

export const EMPTY_TEAM_CHECK_IN: TeamCheckInState = Object.freeze({
  home: false,
  away: false,
});

function storageKey(gameId: string): string {
  return `${SPORTSOS_TEAM_CHECKIN_STORAGE_PREFIX}:${gameId}`;
}

export function readTeamCheckIn(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): TeamCheckInState {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) return { ...EMPTY_TEAM_CHECK_IN };

  try {
    const parsed = JSON.parse(raw) as Partial<TeamCheckInState>;
    return {
      home: parsed.home === true,
      away: parsed.away === true,
    };
  } catch {
    return { ...EMPTY_TEAM_CHECK_IN };
  }
}

export function writeTeamCheckIn(
  storage: Pick<Storage, "setItem">,
  gameId: string,
  state: TeamCheckInState,
): void {
  storage.setItem(storageKey(gameId), JSON.stringify(state));
}

export function setTeamCheckedIn(
  state: TeamCheckInState,
  side: TeamCheckInSide,
  checkedIn: boolean,
): TeamCheckInState {
  return { ...state, [side]: checkedIn };
}

export function areBothTeamsCheckedIn(state: TeamCheckInState): boolean {
  return state.home && state.away;
}
EOF

cat > "$CHECKIN_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  EMPTY_TEAM_CHECK_IN,
  areBothTeamsCheckedIn,
  readTeamCheckIn,
  setTeamCheckedIn,
  writeTeamCheckIn,
} from "../lib/tournament-team-check-in";

describe("Milestone 7.3 team check-in", () => {
  it("defaults both teams to not checked in", () => {
    expect(readTeamCheckIn({ getItem: () => null }, "game-73")).toEqual(
      EMPTY_TEAM_CHECK_IN,
    );
  });

  it("updates one side without mutating the other", () => {
    expect(
      setTeamCheckedIn({ home: false, away: true }, "home", true),
    ).toEqual({ home: true, away: true });
  });

  it("requires both teams for full check-in", () => {
    expect(areBothTeamsCheckedIn({ home: true, away: false })).toBe(false);
    expect(areBothTeamsCheckedIn({ home: true, away: true })).toBe(true);
  });

  it("persists and restores check-in state", () => {
    let value: string | null = null;
    const storage = {
      getItem: () => value,
      setItem: (_key: string, next: string) => { value = next; },
    };

    writeTeamCheckIn(storage, "game-73", { home: true, away: false });
    expect(readTeamCheckIn(storage, "game-73")).toEqual({
      home: true,
      away: false,
    });
  });

  it("fails closed on malformed persisted data", () => {
    expect(
      readTeamCheckIn({ getItem: () => "{not-json" }, "game-73"),
    ).toEqual({ home: false, away: false });
  });
});
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/lib/tournament-pregame-readiness.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes('    | "teamCheckIn"')) {
  const anchor = '    | "scheduledStart"\n    | "rosters"';
  if (!text.includes(anchor)) throw new Error("Readiness id anchor not found.");
  text = text.replace(anchor, '    | "scheduledStart"\n    | "teamCheckIn"\n    | "rosters"');
}

if (!text.includes("teamCheckInReady?: boolean;")) {
  const old = `export function buildPregameReadinessChecks(\n  game: TournamentGameOperationsGame,\n): PregameReadinessCheck[] {`;
  const next = `export function buildPregameReadinessChecks(\n  game: TournamentGameOperationsGame,\n  operationalState: {\n    teamCheckInReady?: boolean;\n  } = {},\n): PregameReadinessCheck[] {`;
  if (!text.includes(old)) throw new Error("buildPregameReadinessChecks anchor not found.");
  text = text.replace(old, next);
}

if (!text.includes('      "teamCheckIn",')) {
  const anchor = `    derivedCheck(\n      "scheduledStart",\n      "Scheduled start",\n      game.readiness.scheduledStartAssigned,\n      "Scheduled start time is present.",\n      "Scheduled start time is missing.",\n    ),`;
  if (!text.includes(anchor)) throw new Error("Scheduled-start check anchor not found.");
  text = text.replace(anchor, `${anchor}\n    derivedCheck(\n      "teamCheckIn",\n      "Team check-in",\n      operationalState.teamCheckInReady === true,\n      "Both teams are checked in.",\n      "Home and away teams must both be checked in before normal game start.",\n    ),`);
}

if (!text.includes("buildPregameReadinessChecks(game, operationalState)")) {
  const old = `export function buildPregameReadinessSummary(\n  game: TournamentGameOperationsGame,\n  testingOverrideEnabled: boolean,\n): PregameReadinessSummary {\n  return summarizePregameReadiness(\n    buildPregameReadinessChecks(game),\n    testingOverrideEnabled,\n  );\n}`;
  const next = `export function buildPregameReadinessSummary(\n  game: TournamentGameOperationsGame,\n  testingOverrideEnabled: boolean,\n  operationalState: {\n    teamCheckInReady?: boolean;\n  } = {},\n): PregameReadinessSummary {\n  return summarizePregameReadiness(\n    buildPregameReadinessChecks(game, operationalState),\n    testingOverrideEnabled,\n  );\n}`;
  if (!text.includes(old)) throw new Error("Readiness summary anchor not found.");
  text = text.replace(old, next);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";
let text = fs.readFileSync(file, "utf8");

function mustReplace(search, replacement, label) {
  if (!text.includes(search)) throw new Error(`Expected ${label} anchor not found.`);
  text = text.replace(search, replacement);
}

if (!text.includes('from "../../lib/tournament-team-check-in";')) {
  const anchor = `} from "../../lib/tournament-pregame-readiness";`;
  mustReplace(anchor, `${anchor}\nimport {\n  areBothTeamsCheckedIn,\n  readTeamCheckIn,\n  setTeamCheckedIn,\n  writeTeamCheckIn,\n  type TeamCheckInSide,\n  type TeamCheckInState,\n} from "../../lib/tournament-team-check-in";`, "readiness import");
}

if (!text.includes("teamCheckInState")) {
  const anchor = `  const [testingOverrideEnabled, setTestingOverrideEnabled] = useState(false);`;
  mustReplace(anchor, `${anchor}\n  const [teamCheckInState, setTeamCheckInState] = useState<TeamCheckInState>({\n    home: false,\n    away: false,\n  });`, "testing override state");
}

if (!text.includes("readTeamCheckIn(window.localStorage")) {
  const anchor = `  const pregameReadinessSummary = useMemo(`;
  mustReplace(anchor, `  useEffect(() => {\n    if (!selectedGame || typeof window === "undefined") {\n      setTeamCheckInState({ home: false, away: false });\n      return;\n    }\n\n    setTeamCheckInState(readTeamCheckIn(window.localStorage, selectedGame.id));\n  }, [selectedGame]);\n\n${anchor}`, "pregame memo");
}

if (!text.includes("teamCheckInReady:")) {
  const old = `        ? buildPregameReadinessSummary(\n            selectedGame,\n            testingOverrideEnabled,\n          )`;
  const next = `        ? buildPregameReadinessSummary(\n            selectedGame,\n            testingOverrideEnabled,\n            {\n              teamCheckInReady: areBothTeamsCheckedIn(teamCheckInState),\n            },\n          )`;
  mustReplace(old, next, "readiness summary call");
  text = text.replace(
    `    [selectedGame, testingOverrideEnabled],`,
    `    [selectedGame, teamCheckInState, testingOverrideEnabled],`,
  );
}

if (!text.includes("const updateTeamCheckIn")) {
  const anchor = `  const toggleTestingOverride = () => {`;
  mustReplace(anchor, `  const updateTeamCheckIn = (\n    side: TeamCheckInSide,\n    checkedIn: boolean,\n  ) => {\n    if (!selectedGame || typeof window === "undefined") return;\n\n    const nextState = setTeamCheckedIn(teamCheckInState, side, checkedIn);\n    setTeamCheckInState(nextState);\n    writeTeamCheckIn(window.localStorage, selectedGame.id, nextState);\n  };\n\n${anchor}`, "testing override toggle");
}

if (!text.includes('data-testid="team-check-in-panel"')) {
  const anchor = `            <aside className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">`;
  const panel = `            <section\n              data-testid="team-check-in-panel"\n              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"\n            >\n              <div className="flex flex-wrap items-center justify-between gap-3">\n                <div>\n                  <h2 className="font-semibold text-slate-100">Team check-in</h2>\n                  <p className="mt-1 text-xs text-slate-500">\n                    Confirm each team has arrived and reported for this game.\n                  </p>\n                </div>\n                <span className={areBothTeamsCheckedIn(teamCheckInState) ? "text-sm font-semibold text-emerald-400" : "text-sm font-semibold text-amber-400"}>\n                  {areBothTeamsCheckedIn(teamCheckInState) ? "Both checked in" : "Waiting"}\n                </span>\n              </div>\n\n              <div className="mt-4 grid gap-3 md:grid-cols-2">\n                {[\n                  { side: "home" as const, label: selectedGame.homeTeamName },\n                  { side: "away" as const, label: selectedGame.awayTeamName },\n                ].map(({ side, label }) => {\n                  const checkedIn = teamCheckInState[side];\n                  return (\n                    <div key={side} className="rounded-lg border border-slate-800 bg-slate-950/60 p-4">\n                      <div className="flex items-center justify-between gap-3">\n                        <div>\n                          <div className="text-xs uppercase tracking-wide text-slate-500">{side}</div>\n                          <div className="mt-1 font-semibold text-slate-200">{label}</div>\n                        </div>\n                        <span className={checkedIn ? "text-sm font-semibold text-emerald-400" : "text-sm font-semibold text-slate-500"}>\n                          {checkedIn ? "Checked in" : "Not checked in"}\n                        </span>\n                      </div>\n                      <button\n                        type="button"\n                        data-testid={\`team-check-in-\${side}\`}\n                        onClick={() => updateTeamCheckIn(side, !checkedIn)}\n                        className="mt-4 w-full rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900"\n                      >\n                        {checkedIn ? "Undo check-in" : "Mark checked in"}\n                      </button>\n                    </div>\n                  );\n                })}\n              </div>\n\n              <p className="mt-3 text-xs leading-5 text-slate-500">\n                Check-in is stored per game for operations testing. It feeds actual readiness, while Testing Override affects only effective readiness.\n              </p>\n            </section>\n\n`;
  mustReplace(anchor, panel + anchor, "pregame readiness aside");
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - home and away team check-in controls"
echo "  - per-game local check-in persistence"
echo "  - team check-in as a required readiness check"
echo "  - actual/effective readiness separation preserved"
echo "  - testing override remains non-mutating"
echo "  - Milestone 7.3 unit tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Validate:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build && \\"
echo "  docker compose up -d --build dashboard && \\"
echo "  npm run test:e2e:docker"
