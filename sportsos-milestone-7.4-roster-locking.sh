#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.4-roster-locking"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
CHECKIN_LIB="apps/dashboard/lib/tournament-team-check-in.ts"
ROSTER_LOCK_LIB="apps/dashboard/lib/tournament-roster-lock.ts"
ROSTER_LOCK_TEST="apps/dashboard/test/tournament-roster-lock-7.4.test.ts"

for file in "$WORKSPACE" "$READINESS_LIB" "$CHECKIN_LIB"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'teamCheckInReady' "$READINESS_LIB" || {
  echo "ERROR: Milestone 7.3 readiness integration not found." >&2
  exit 1
}

grep -Fq 'team-check-in-panel' "$WORKSPACE" || {
  echo "ERROR: Milestone 7.3 team check-in UI not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$READINESS_LIB")" \
  "$BACKUP_DIR/$(dirname "$ROSTER_LOCK_LIB")" \
  "$BACKUP_DIR/$(dirname "$ROSTER_LOCK_TEST")"

for file in "$WORKSPACE" "$READINESS_LIB" "$ROSTER_LOCK_LIB" "$ROSTER_LOCK_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$ROSTER_LOCK_LIB" <<'EOF'
export const SPORTSOS_ROSTER_LOCK_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:roster-lock";

export type RosterLockSide = "home" | "away";

export type RosterLockState = {
  home: boolean;
  away: boolean;
};

export const EMPTY_ROSTER_LOCK_STATE: RosterLockState = Object.freeze({
  home: false,
  away: false,
});

function storageKey(gameId: string): string {
  return `${SPORTSOS_ROSTER_LOCK_STORAGE_PREFIX}:${gameId}`;
}

export function readRosterLockState(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): RosterLockState {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return { ...EMPTY_ROSTER_LOCK_STATE };
  }

  try {
    const parsed = JSON.parse(raw) as Partial<RosterLockState>;

    return {
      home: parsed.home === true,
      away: parsed.away === true,
    };
  } catch {
    return { ...EMPTY_ROSTER_LOCK_STATE };
  }
}

export function writeRosterLockState(
  storage: Pick<Storage, "setItem">,
  gameId: string,
  state: RosterLockState,
): void {
  storage.setItem(storageKey(gameId), JSON.stringify(state));
}

export function setRosterLocked(
  state: RosterLockState,
  side: RosterLockSide,
  locked: boolean,
): RosterLockState {
  return {
    ...state,
    [side]: locked,
  };
}

export function areBothRostersLocked(state: RosterLockState): boolean {
  return state.home && state.away;
}

export function canLockRoster(
  checkedIn: boolean,
  testingOverrideEnabled: boolean,
): boolean {
  return checkedIn || testingOverrideEnabled;
}
EOF

cat > "$ROSTER_LOCK_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  EMPTY_ROSTER_LOCK_STATE,
  areBothRostersLocked,
  canLockRoster,
  readRosterLockState,
  setRosterLocked,
  writeRosterLockState,
} from "../lib/tournament-roster-lock";

describe("Milestone 7.4 roster locking", () => {
  it("defaults both rosters to unlocked", () => {
    expect(
      readRosterLockState(
        { getItem: () => null },
        "game-74",
      ),
    ).toEqual(EMPTY_ROSTER_LOCK_STATE);
  });

  it("locks one roster without mutating the other side", () => {
    expect(
      setRosterLocked(
        { home: false, away: true },
        "home",
        true,
      ),
    ).toEqual({
      home: true,
      away: true,
    });
  });

  it("requires both rosters for full roster readiness", () => {
    expect(
      areBothRostersLocked({
        home: true,
        away: false,
      }),
    ).toBe(false);

    expect(
      areBothRostersLocked({
        home: true,
        away: true,
      }),
    ).toBe(true);
  });

  it("requires check-in before normal locking", () => {
    expect(canLockRoster(false, false)).toBe(false);
    expect(canLockRoster(true, false)).toBe(true);
  });

  it("allows the existing testing override to bypass the check-in gate", () => {
    expect(canLockRoster(false, true)).toBe(true);
  });

  it("persists and restores per-game roster locks", () => {
    let value: string | null = null;

    const storage = {
      getItem: () => value,
      setItem: (_key: string, nextValue: string) => {
        value = nextValue;
      },
    };

    writeRosterLockState(storage, "game-74", {
      home: true,
      away: false,
    });

    expect(readRosterLockState(storage, "game-74")).toEqual({
      home: true,
      away: false,
    });
  });

  it("fails closed for malformed persisted data", () => {
    expect(
      readRosterLockState(
        { getItem: () => "{broken-json" },
        "game-74",
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

if (!text.includes('"rosterLock"')) {
  const anchor = `    | "teamCheckIn"`;
  if (!text.includes(anchor)) {
    throw new Error("Could not locate teamCheckIn readiness id.");
  }

  text = text.replace(anchor, `${anchor}\n    | "rosterLock"`);
}

if (!text.includes("rosterLockReady?: boolean;")) {
  const anchor = `    teamCheckInReady?: boolean;`;
  if (!text.includes(anchor)) {
    throw new Error("Could not locate operational readiness state.");
  }

  text = text.replace(
    anchor,
`${anchor}
    rosterLockReady?: boolean;`,
  );
}

if (!text.includes('"Roster lock"')) {
  const checkInRegex = /(\s*derivedCheck\(\s*"teamCheckIn",[\s\S]*?\),)/m;
  const match = text.match(checkInRegex);

  if (!match) {
    throw new Error("Could not locate Team check-in readiness check.");
  }

  const rosterCheck = `
    derivedCheck(
      "rosterLock",
      "Roster lock",
      operationalState.rosterLockReady === true,
      "Both team rosters are locked for game operations.",
      "Home and away rosters must both be locked before normal game start.",
    ),`;

  text = text.replace(match[0], `${match[0]}${rosterCheck}`);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function assertFound(condition, message) {
  if (!condition) throw new Error(message);
}

if (!text.includes('from "../../lib/tournament-roster-lock";')) {
  const importAnchor =
`} from "../../lib/tournament-team-check-in";`;

  assertFound(
    text.includes(importAnchor),
    "Could not locate team check-in import.",
  );

  text = text.replace(
    importAnchor,
`${importAnchor}
import {
  areBothRostersLocked,
  canLockRoster,
  readRosterLockState,
  setRosterLocked,
  writeRosterLockState,
  type RosterLockSide,
  type RosterLockState,
} from "../../lib/tournament-roster-lock";`,
  );
}

if (!text.includes("const [rosterLockState")) {
  const stateAnchor = /const \[teamCheckInState,[\s\S]*?\}\);/m;
  const match = text.match(stateAnchor);

  assertFound(
    match,
    "Could not locate team check-in state.",
  );

  text = text.replace(
    match[0],
`${match[0]}
  const [rosterLockState, setRosterLockState] =
    useState<RosterLockState>({
      home: false,
      away: false,
    });`,
  );
}

if (!text.includes("readRosterLockState(window.localStorage")) {
  const checkInEffectRegex =
    /useEffect\(\(\) => \{\s*if \(!selectedGame \|\| typeof window === "undefined"\) \{[\s\S]*?readTeamCheckIn\(window\.localStorage, selectedGame\.id\),\s*\);\s*\}, \[selectedGame\]\);/m;

  const match = text.match(checkInEffectRegex);

  assertFound(
    match,
    "Could not locate team check-in persistence effect.",
  );

  const rosterEffect = `

  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setRosterLockState({
        home: false,
        away: false,
      });
      return;
    }

    setRosterLockState(
      readRosterLockState(window.localStorage, selectedGame.id),
    );
  }, [selectedGame]);`;

  text = text.replace(match[0], `${match[0]}${rosterEffect}`);
}

if (!text.includes("rosterLockReady:")) {
  const operationalAnchor =
`              teamCheckInReady:
                areBothTeamsCheckedIn(teamCheckInState),`;

  assertFound(
    text.includes(operationalAnchor),
    "Could not locate teamCheckInReady readiness input.",
  );

  text = text.replace(
    operationalAnchor,
`${operationalAnchor}
              rosterLockReady:
                areBothRostersLocked(rosterLockState),`,
  );

  text = text.replace(
    "[selectedGame, teamCheckInState, testingOverrideEnabled]",
    "[selectedGame, rosterLockState, teamCheckInState, testingOverrideEnabled]",
  );
}

if (!text.includes("const updateRosterLock")) {
  const anchor = "const updateTeamCheckIn";

  const index = text.indexOf(anchor);
  assertFound(
    index >= 0,
    "Could not locate updateTeamCheckIn function.",
  );

  const toggleIndex = text.indexOf("const toggleTestingOverride");
  assertFound(
    toggleIndex > index,
    "Could not locate testing override toggle after team check-in updater.",
  );

  const updateFn = `  const updateRosterLock = (
    side: RosterLockSide,
    locked: boolean,
  ) => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    const checkedIn = teamCheckInState[side];

    if (
      locked &&
      !canLockRoster(
        checkedIn,
        testingOverrideEnabled,
      )
    ) {
      return;
    }

    const nextState = setRosterLocked(
      rosterLockState,
      side,
      locked,
    );

    setRosterLockState(nextState);
    writeRosterLockState(
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

if (!text.includes('data-testid="roster-lock-panel"')) {
  const checkInPanelIndex = text.indexOf(
    'data-testid="team-check-in-panel"',
  );

  assertFound(
    checkInPanelIndex >= 0,
    "Could not locate Team Check-In panel.",
  );

  const sectionStart = text.lastIndexOf(
    "<section",
    checkInPanelIndex,
  );

  assertFound(
    sectionStart >= 0,
    "Could not locate Team Check-In section start.",
  );

  const nextAside = text.indexOf(
    '<aside className="rounded-xl',
    checkInPanelIndex,
  );

  assertFound(
    nextAside > checkInPanelIndex,
    "Could not locate readiness panel following Team Check-In.",
  );

  const rosterPanel = `            <section
              data-testid="roster-lock-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Roster locking
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Freeze each team's game roster after check-in.
                  </p>
                </div>

                <span
                  className={
                    areBothRostersLocked(rosterLockState)
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {areBothRostersLocked(rosterLockState)
                    ? "Both locked"
                    : "Pending"}
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
                  const locked = rosterLockState[side];
                  const checkedIn = teamCheckInState[side];
                  const lockAllowed = canLockRoster(
                    checkedIn,
                    testingOverrideEnabled,
                  );

                  return (
                    <div
                      key={side}
                      className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            {side}
                          </div>
                          <div className="mt-1 font-semibold text-slate-200">
                            {label}
                          </div>
                          <div className="mt-1 text-xs text-slate-500">
                            {checkedIn
                              ? "Team checked in"
                              : testingOverrideEnabled
                                ? "Check-in bypassed by testing override"
                                : "Check-in required before locking"}
                          </div>
                        </div>

                        <span
                          className={
                            locked
                              ? "text-sm font-semibold text-emerald-400"
                              : "text-sm font-semibold text-slate-500"
                          }
                        >
                          {locked ? "Locked" : "Unlocked"}
                        </span>
                      </div>

                      <button
                        type="button"
                        data-testid={\`roster-lock-\${side}\`}
                        disabled={!locked && !lockAllowed}
                        onClick={() =>
                          updateRosterLock(side, !locked)
                        }
                        className="mt-4 w-full rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900 disabled:cursor-not-allowed disabled:opacity-40"
                      >
                        {locked ? "Unlock roster" : "Lock roster"}
                      </button>
                    </div>
                  );
                })}
              </div>

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Roster locks are per-game operational state in Milestone 7.4.
                Testing override may bypass the prerequisite check-in gate but
                does not silently mark the roster as locked.
              </p>
            </section>

`;

  text =
    text.slice(0, nextAside) +
    rosterPanel +
    text.slice(nextAside);
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - home roster lock"
echo "  - away roster lock"
echo "  - per-game local roster-lock persistence"
echo "  - normal lock requires corresponding team check-in"
echo "  - testing override may bypass the lock prerequisite"
echo "  - roster locks feed actual pregame readiness"
echo "  - automated Milestone 7.4 tests"
echo
echo "Important:"
echo "  Testing override never silently changes roster-lock state."
echo "  It only permits test operators to exercise the lock action."
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
