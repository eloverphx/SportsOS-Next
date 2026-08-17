#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.3-team-check-in-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
CHECKIN_LIB="apps/dashboard/lib/tournament-team-check-in.ts"
CHECKIN_TEST="apps/dashboard/test/tournament-team-check-in-7.3.test.ts"

for file in "$WORKSPACE" "$READINESS_LIB"; do
  [[ -f "$file" ]] || { echo "ERROR: required file missing: $file" >&2; exit 1; }
done

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

  if (!raw) {
    return { ...EMPTY_TEAM_CHECK_IN };
  }

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
  return {
    ...state,
    [side]: checkedIn,
  };
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
    const storage = { getItem: () => null };

    expect(readTeamCheckIn(storage, "game-73")).toEqual(
      EMPTY_TEAM_CHECK_IN,
    );
  });

  it("updates one side without mutating the other", () => {
    expect(
      setTeamCheckedIn(
        { home: false, away: true },
        "home",
        true,
      ),
    ).toEqual({
      home: true,
      away: true,
    });
  });

  it("requires both teams for full check-in", () => {
    expect(
      areBothTeamsCheckedIn({
        home: true,
        away: false,
      }),
    ).toBe(false);

    expect(
      areBothTeamsCheckedIn({
        home: true,
        away: true,
      }),
    ).toBe(true);
  });

  it("persists and restores state", () => {
    let value: string | null = null;

    const storage = {
      getItem: () => value,
      setItem: (_key: string, nextValue: string) => {
        value = nextValue;
      },
    };

    writeTeamCheckIn(storage, "game-73", {
      home: true,
      away: false,
    });

    expect(readTeamCheckIn(storage, "game-73")).toEqual({
      home: true,
      away: false,
    });
  });

  it("fails closed for malformed persisted data", () => {
    expect(
      readTeamCheckIn(
        { getItem: () => "{broken-json" },
        "game-73",
      ),
    ).toEqual({
      home: false,
      away: false,
    });
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file = "apps/dashboard/lib/tournament-pregame-readiness.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes('"teamCheckIn"')) {
  const anchor = `    | "scheduledStart"`;
  if (!text.includes(anchor)) {
    throw new Error("Could not locate readiness id union.");
  }
  text = text.replace(anchor, `${anchor}\n    | "teamCheckIn"`);
}

if (!text.includes("teamCheckInReady?: boolean;")) {
  const signature = /export function buildPregameReadinessChecks\(\s*game: TournamentGameOperationsGame,\s*\): PregameReadinessCheck\[\] \{/m;

  if (!signature.test(text)) {
    throw new Error("Could not locate buildPregameReadinessChecks signature.");
  }

  text = text.replace(
    signature,
`export function buildPregameReadinessChecks(
  game: TournamentGameOperationsGame,
  operationalState: {
    teamCheckInReady?: boolean;
  } = {},
): PregameReadinessCheck[] {`,
  );
}

if (!text.includes('"Team check-in"')) {
  const scheduled = /(\s*derivedCheck\(\s*"scheduledStart",[\s\S]*?\),)/m;
  const match = text.match(scheduled);

  if (!match) {
    throw new Error("Could not locate scheduled-start readiness check.");
  }

  const check = `
    derivedCheck(
      "teamCheckIn",
      "Team check-in",
      operationalState.teamCheckInReady === true,
      "Both teams are checked in.",
      "Home and away teams must both be checked in before normal game start.",
    ),`;

  text = text.replace(match[0], `${match[0]}${check}`);
}

if (!text.includes("buildPregameReadinessChecks(game, operationalState)")) {
  const summarySignature = /export function buildPregameReadinessSummary\(\s*game: TournamentGameOperationsGame,\s*testingOverrideEnabled: boolean,\s*\): PregameReadinessSummary \{/m;

  if (!summarySignature.test(text)) {
    throw new Error("Could not locate buildPregameReadinessSummary signature.");
  }

  text = text.replace(
    summarySignature,
`export function buildPregameReadinessSummary(
  game: TournamentGameOperationsGame,
  testingOverrideEnabled: boolean,
  operationalState: {
    teamCheckInReady?: boolean;
  } = {},
): PregameReadinessSummary {`,
  );

  text = text.replace(
    "buildPregameReadinessChecks(game),",
    "buildPregameReadinessChecks(game, operationalState),",
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function requireAnchor(condition, message) {
  if (!condition) throw new Error(message);
}

if (!text.includes('from "../../lib/tournament-team-check-in";')) {
  const readinessImportEnd =
    '} from "../../lib/tournament-pregame-readiness";';

  requireAnchor(
    text.includes(readinessImportEnd),
    "Could not locate tournament pregame readiness import.",
  );

  text = text.replace(
    readinessImportEnd,
`${readinessImportEnd}
import {
  areBothTeamsCheckedIn,
  readTeamCheckIn,
  setTeamCheckedIn,
  writeTeamCheckIn,
  type TeamCheckInSide,
  type TeamCheckInState,
} from "../../lib/tournament-team-check-in";`,
  );
}

if (!text.includes("const [teamCheckInState")) {
  const componentMatch = text.match(
    /export function TournamentGameOperationsWorkspace[^{]*\{/
  );

  requireAnchor(
    componentMatch,
    "Could not locate TournamentGameOperationsWorkspace function.",
  );

  const insertionPoint =
    componentMatch.index + componentMatch[0].length;

  const state = `
  const [teamCheckInState, setTeamCheckInState] =
    useState<TeamCheckInState>({
      home: false,
      away: false,
    });
`;

  text =
    text.slice(0, insertionPoint) +
    state +
    text.slice(insertionPoint);
}

if (!text.includes("readTeamCheckIn(window.localStorage")) {
  const readinessMemoIndex = text.indexOf(
    "const pregameReadinessSummary = useMemo("
  );

  requireAnchor(
    readinessMemoIndex >= 0,
    "Could not locate pregameReadinessSummary memo.",
  );

  const effect = `  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setTeamCheckInState({
        home: false,
        away: false,
      });
      return;
    }

    setTeamCheckInState(
      readTeamCheckIn(window.localStorage, selectedGame.id),
    );
  }, [selectedGame]);

`;

  text =
    text.slice(0, readinessMemoIndex) +
    effect +
    text.slice(readinessMemoIndex);
}

if (!text.includes("teamCheckInReady:")) {
  const callRegex =
    /buildPregameReadinessSummary\(\s*selectedGame,\s*testingOverrideEnabled,\s*\)/m;

  requireAnchor(
    callRegex.test(text),
    "Could not locate existing 7.2 readiness summary call.",
  );

  text = text.replace(
    callRegex,
`buildPregameReadinessSummary(
            selectedGame,
            testingOverrideEnabled,
            {
              teamCheckInReady:
                areBothTeamsCheckedIn(teamCheckInState),
            },
          )`,
  );

  const dependencyRegex =
    /\[selectedGame,\s*testingOverrideEnabled\]/;

  if (dependencyRegex.test(text)) {
    text = text.replace(
      dependencyRegex,
      "[selectedGame, teamCheckInState, testingOverrideEnabled]",
    );
  }
}

if (!text.includes("const updateTeamCheckIn")) {
  const toggleIndex = text.indexOf(
    "const toggleTestingOverride"
  );

  requireAnchor(
    toggleIndex >= 0,
    "Could not locate testing override toggle function.",
  );

  const updateFn = `  const updateTeamCheckIn = (
    side: TeamCheckInSide,
    checkedIn: boolean,
  ) => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    const nextState = setTeamCheckedIn(
      teamCheckInState,
      side,
      checkedIn,
    );

    setTeamCheckInState(nextState);
    writeTeamCheckIn(
      window.localStorage,
      selectedGame.id,
      nextState,
    );
  };

`;

  text =
    text.slice(0, toggleIndex) +
    updateFn +
    text.slice(toggleIndex);
}

if (!text.includes('data-testid="team-check-in-panel"')) {
  const readinessHeading = "Pregame readiness";
  const headingIndex = text.indexOf(readinessHeading);

  requireAnchor(
    headingIndex >= 0,
    "Could not locate Pregame readiness panel.",
  );

  const asideIndex = text.lastIndexOf(
    '<aside className="rounded-xl',
    headingIndex,
  );

  requireAnchor(
    asideIndex >= 0,
    "Could not locate readiness panel opening aside.",
  );

  const panel = `            <section
              data-testid="team-check-in-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Team check-in
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Confirm each team has arrived and reported for this game.
                  </p>
                </div>

                <span
                  className={
                    areBothTeamsCheckedIn(teamCheckInState)
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {areBothTeamsCheckedIn(teamCheckInState)
                    ? "Both checked in"
                    : "Waiting"}
                </span>
              </div>

              <div className="mt-4 grid gap-3 md:grid-cols-2">
                {[
                  {
                    side: "home" as const,
                    label: selectedGame.homeTeamName,
                  },
                  {
                    side: "away" as const,
                    label: selectedGame.awayTeamName,
                  },
                ].map(({ side, label }) => {
                  const checkedIn = teamCheckInState[side];

                  return (
                    <div
                      key={side}
                      className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            {side}
                          </div>
                          <div className="mt-1 font-semibold text-slate-200">
                            {label}
                          </div>
                        </div>

                        <span
                          className={
                            checkedIn
                              ? "text-sm font-semibold text-emerald-400"
                              : "text-sm font-semibold text-slate-500"
                          }
                        >
                          {checkedIn ? "Checked in" : "Not checked in"}
                        </span>
                      </div>

                      <button
                        type="button"
                        data-testid={\`team-check-in-\${side}\`}
                        onClick={() =>
                          updateTeamCheckIn(side, !checkedIn)
                        }
                        className="mt-4 w-full rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900"
                      >
                        {checkedIn
                          ? "Undo check-in"
                          : "Mark checked in"}
                      </button>
                    </div>
                  );
                })}
              </div>

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Check-in is stored per game for local operations testing.
                Testing override may bypass readiness, but it does not alter
                either team's actual check-in state.
              </p>
            </section>

`;

  text =
    text.slice(0, asideIndex) +
    panel +
    text.slice(asideIndex);
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.3 repair installed"
echo "============================================================"
echo
echo "This repair is safe after the earlier partial failure."
echo
echo "Installed/verified:"
echo "  - home and away team check-in controls"
echo "  - per-game local check-in persistence"
echo "  - both-team check-in as a required readiness condition"
echo "  - testing override remains separate from actual state"
echo "  - Milestone 7.3 unit tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build && \\"
echo "  docker compose up -d --build dashboard && \\"
echo "  npm run test:e2e:docker"
