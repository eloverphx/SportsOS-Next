#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.5-officials-assignment"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
ROSTER_LOCK_LIB="apps/dashboard/lib/tournament-roster-lock.ts"
OFFICIALS_LIB="apps/dashboard/lib/tournament-officials-assignment.ts"
OFFICIALS_TEST="apps/dashboard/test/tournament-officials-assignment-7.5.test.ts"
READINESS_TEST="apps/dashboard/test/tournament-pregame-readiness-7.2.test.ts"

for file in "$WORKSPACE" "$READINESS_LIB" "$ROSTER_LOCK_LIB" "$READINESS_TEST"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'rosterLockReady' "$READINESS_LIB" || {
  echo "ERROR: Milestone 7.4 readiness integration not found." >&2
  exit 1
}

grep -Fq 'roster-lock-panel' "$WORKSPACE" || {
  echo "ERROR: Milestone 7.4 roster lock UI not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$READINESS_LIB")" \
  "$BACKUP_DIR/$(dirname "$OFFICIALS_LIB")" \
  "$BACKUP_DIR/$(dirname "$OFFICIALS_TEST")" \
  "$BACKUP_DIR/$(dirname "$READINESS_TEST")"

for file in "$WORKSPACE" "$READINESS_LIB" "$OFFICIALS_LIB" "$OFFICIALS_TEST" "$READINESS_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$OFFICIALS_LIB" <<'EOF'
export const SPORTSOS_OFFICIALS_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:officials";

export type OfficialsAssignmentState = {
  referee1: string;
  referee2: string;
  linesman1: string;
  linesman2: string;
};

export const EMPTY_OFFICIALS_ASSIGNMENT: OfficialsAssignmentState =
  Object.freeze({
    referee1: "",
    referee2: "",
    linesman1: "",
    linesman2: "",
  });

function storageKey(gameId: string): string {
  return `${SPORTSOS_OFFICIALS_STORAGE_PREFIX}:${gameId}`;
}

export function normalizeOfficialName(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function readOfficialsAssignment(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): OfficialsAssignmentState {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return { ...EMPTY_OFFICIALS_ASSIGNMENT };
  }

  try {
    const parsed = JSON.parse(raw) as Partial<OfficialsAssignmentState>;

    return {
      referee1: normalizeOfficialName(parsed.referee1 ?? ""),
      referee2: normalizeOfficialName(parsed.referee2 ?? ""),
      linesman1: normalizeOfficialName(parsed.linesman1 ?? ""),
      linesman2: normalizeOfficialName(parsed.linesman2 ?? ""),
    };
  } catch {
    return { ...EMPTY_OFFICIALS_ASSIGNMENT };
  }
}

export function writeOfficialsAssignment(
  storage: Pick<Storage, "setItem">,
  gameId: string,
  state: OfficialsAssignmentState,
): void {
  storage.setItem(
    storageKey(gameId),
    JSON.stringify({
      referee1: normalizeOfficialName(state.referee1),
      referee2: normalizeOfficialName(state.referee2),
      linesman1: normalizeOfficialName(state.linesman1),
      linesman2: normalizeOfficialName(state.linesman2),
    }),
  );
}

export function hasRequiredOfficials(
  state: OfficialsAssignmentState,
): boolean {
  return (
    normalizeOfficialName(state.referee1).length > 0 &&
    normalizeOfficialName(state.referee2).length > 0
  );
}

export function hasCompleteOfficialsCrew(
  state: OfficialsAssignmentState,
): boolean {
  return (
    hasRequiredOfficials(state) &&
    normalizeOfficialName(state.linesman1).length > 0 &&
    normalizeOfficialName(state.linesman2).length > 0
  );
}
EOF

cat > "$OFFICIALS_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  EMPTY_OFFICIALS_ASSIGNMENT,
  hasCompleteOfficialsCrew,
  hasRequiredOfficials,
  normalizeOfficialName,
  readOfficialsAssignment,
  writeOfficialsAssignment,
} from "../lib/tournament-officials-assignment";

describe("Milestone 7.5 officials assignment", () => {
  it("normalizes official names", () => {
    expect(normalizeOfficialName("  Alex   Smith  ")).toBe("Alex Smith");
  });

  it("defaults to an empty assignment", () => {
    expect(
      readOfficialsAssignment(
        { getItem: () => null },
        "game-75",
      ),
    ).toEqual(EMPTY_OFFICIALS_ASSIGNMENT);
  });

  it("requires two referees for required readiness", () => {
    expect(
      hasRequiredOfficials({
        referee1: "Ref One",
        referee2: "",
        linesman1: "",
        linesman2: "",
      }),
    ).toBe(false);

    expect(
      hasRequiredOfficials({
        referee1: "Ref One",
        referee2: "Ref Two",
        linesman1: "",
        linesman2: "",
      }),
    ).toBe(true);
  });

  it("distinguishes required officials from a complete crew", () => {
    const assignment = {
      referee1: "Ref One",
      referee2: "Ref Two",
      linesman1: "",
      linesman2: "",
    };

    expect(hasRequiredOfficials(assignment)).toBe(true);
    expect(hasCompleteOfficialsCrew(assignment)).toBe(false);
  });

  it("persists and restores assignments", () => {
    let value: string | null = null;

    const storage = {
      getItem: () => value,
      setItem: (_key: string, nextValue: string) => {
        value = nextValue;
      },
    };

    writeOfficialsAssignment(storage, "game-75", {
      referee1: " Ref One ",
      referee2: "Ref   Two",
      linesman1: "Line One",
      linesman2: "Line Two",
    });

    expect(readOfficialsAssignment(storage, "game-75")).toEqual({
      referee1: "Ref One",
      referee2: "Ref Two",
      linesman1: "Line One",
      linesman2: "Line Two",
    });
  });

  it("fails closed for malformed persisted data", () => {
    expect(
      readOfficialsAssignment(
        { getItem: () => "{bad-json" },
        "game-75",
      ),
    ).toEqual({
      referee1: "",
      referee2: "",
      linesman1: "",
      linesman2: "",
    });
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file = "apps/dashboard/lib/tournament-pregame-readiness.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes('"officials"')) {
  const anchor = `    | "rosterLock"`;
  if (!text.includes(anchor)) {
    throw new Error("Could not locate rosterLock readiness id.");
  }

  text = text.replace(anchor, `${anchor}\n    | "officials"`);
}

for (const fn of [
  "buildPregameReadinessChecks",
  "buildPregameReadinessSummary",
]) {
  const re = new RegExp(
    `(export function ${fn}\\([\\s\\S]*?operationalState:\\s*\\{)([\\s\\S]*?)(\\}\\s*=\\s*\\{\\},)`
  );

  const match = text.match(re);

  if (!match) {
    throw new Error(`Could not locate operationalState type for ${fn}.`);
  }

  let body = match[2];

  if (!body.includes("officialsReady?: boolean;")) {
    body += `\n    officialsReady?: boolean;`;
  }

  text = text.replace(
    match[0],
    `${match[1]}${body}${match[3]}`,
  );
}

if (!text.includes('"Officials assigned"')) {
  const rosterRegex = /(\s*derivedCheck\(\s*"rosterLock",[\s\S]*?\),)/m;
  const match = text.match(rosterRegex);

  if (!match) {
    throw new Error("Could not locate roster lock readiness check.");
  }

  const officialsCheck = `
    derivedCheck(
      "officials",
      "Officials assigned",
      operationalState.officialsReady === true,
      "Required officials are assigned.",
      "Two referees must be assigned before normal game start.",
    ),`;

  text = text.replace(match[0], `${match[0]}${officialsCheck}`);
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

if (!text.includes('from "../../lib/tournament-officials-assignment";')) {
  const importAnchor =
`} from "../../lib/tournament-roster-lock";`;

  assertFound(
    text.includes(importAnchor),
    "Could not locate roster-lock import.",
  );

  text = text.replace(
    importAnchor,
`${importAnchor}
import {
  hasCompleteOfficialsCrew,
  hasRequiredOfficials,
  readOfficialsAssignment,
  writeOfficialsAssignment,
  type OfficialsAssignmentState,
} from "../../lib/tournament-officials-assignment";`,
  );
}

if (!text.includes("const [officialsAssignment")) {
  const stateAnchor = /const \[rosterLockState,[\s\S]*?\}\);/m;
  const match = text.match(stateAnchor);

  assertFound(
    match,
    "Could not locate roster lock state.",
  );

  text = text.replace(
    match[0],
`${match[0]}
  const [officialsAssignment, setOfficialsAssignment] =
    useState<OfficialsAssignmentState>({
      referee1: "",
      referee2: "",
      linesman1: "",
      linesman2: "",
    });`,
  );
}

if (!text.includes("readOfficialsAssignment(window.localStorage")) {
  const readinessMemoIndex = text.indexOf(
    "const pregameReadinessSummary = useMemo("
  );

  assertFound(
    readinessMemoIndex >= 0,
    "Could not locate pregame readiness memo.",
  );

  const effect = `  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setOfficialsAssignment({
        referee1: "",
        referee2: "",
        linesman1: "",
        linesman2: "",
      });
      return;
    }

    setOfficialsAssignment(
      readOfficialsAssignment(
        window.localStorage,
        selectedGame.id,
      ),
    );
  }, [selectedGame]);

`;

  text =
    text.slice(0, readinessMemoIndex) +
    effect +
    text.slice(readinessMemoIndex);
}

if (!text.includes("officialsReady:")) {
  const operationalAnchor =
`              rosterLockReady:
                areBothRostersLocked(rosterLockState),`;

  assertFound(
    text.includes(operationalAnchor),
    "Could not locate rosterLockReady readiness input.",
  );

  text = text.replace(
    operationalAnchor,
`${operationalAnchor}
              officialsReady:
                hasRequiredOfficials(officialsAssignment),`,
  );

  text = text.replace(
    "[selectedGame, rosterLockState, teamCheckInState, testingOverrideEnabled]",
    "[officialsAssignment, selectedGame, rosterLockState, teamCheckInState, testingOverrideEnabled]",
  );
}

if (!text.includes("const updateOfficialAssignment")) {
  const toggleIndex = text.indexOf("const toggleTestingOverride");

  assertFound(
    toggleIndex >= 0,
    "Could not locate testing override toggle.",
  );

  const fn = `  const updateOfficialAssignment = (
    field: keyof OfficialsAssignmentState,
    value: string,
  ) => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    const nextState = {
      ...officialsAssignment,
      [field]: value,
    };

    setOfficialsAssignment(nextState);
    writeOfficialsAssignment(
      window.localStorage,
      selectedGame.id,
      nextState,
    );
  };

`;

  text =
    text.slice(0, toggleIndex) +
    fn +
    text.slice(toggleIndex);
}

if (!text.includes('data-testid="officials-assignment-panel"')) {
  const readinessHeadingIndex = text.indexOf("Pregame readiness");

  assertFound(
    readinessHeadingIndex >= 0,
    "Could not locate pregame readiness panel.",
  );

  const readinessAside = text.lastIndexOf(
    '<aside className="rounded-xl',
    readinessHeadingIndex,
  );

  assertFound(
    readinessAside >= 0,
    "Could not locate pregame readiness aside.",
  );

  const panel = `            <section
              data-testid="officials-assignment-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Officials assignment
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Assign the on-ice crew for this game.
                  </p>
                </div>

                <span
                  className={
                    hasRequiredOfficials(officialsAssignment)
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {hasCompleteOfficialsCrew(officialsAssignment)
                    ? "Crew complete"
                    : hasRequiredOfficials(officialsAssignment)
                      ? "Required officials ready"
                      : "Assignment incomplete"}
                </span>
              </div>

              <div className="mt-4 grid gap-3 md:grid-cols-2">
                {[
                  {
                    field: "referee1" as const,
                    label: "Referee 1",
                    required: true,
                  },
                  {
                    field: "referee2" as const,
                    label: "Referee 2",
                    required: true,
                  },
                  {
                    field: "linesman1" as const,
                    label: "Linesman 1",
                    required: false,
                  },
                  {
                    field: "linesman2" as const,
                    label: "Linesman 2",
                    required: false,
                  },
                ].map(({ field, label, required }) => (
                  <label
                    key={field}
                    className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-semibold text-slate-200">
                        {label}
                      </span>
                      <span className="text-[10px] uppercase tracking-wide text-slate-500">
                        {required ? "required" : "optional"}
                      </span>
                    </div>

                    <input
                      type="text"
                      data-testid={\`official-\${field}\`}
                      value={officialsAssignment[field]}
                      onChange={(event) =>
                        updateOfficialAssignment(
                          field,
                          event.target.value,
                        )
                      }
                      placeholder="Official name"
                      className="mt-3 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-slate-500"
                    />
                  </label>
                ))}
              </div>

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Milestone 7.5 treats two assigned referees as the required
                readiness threshold. Linesmen remain visible as optional crew
                positions until tournament rules make them mandatory.
              </p>
            </section>

`;

  text =
    text.slice(0, readinessAside) +
    panel +
    text.slice(readinessAside);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/test/tournament-pregame-readiness-7.2.test.ts";

let text = fs.readFileSync(file, "utf8");

if (!text.includes("accepts officials operational readiness")) {
  text += `

describe("Milestone 7.5 readiness integration", () => {
  it("accepts officials operational readiness", () => {
    const summary = buildPregameReadinessSummary(
      game(),
      false,
      {
        teamCheckInReady: true,
        rosterLockReady: true,
        officialsReady: true,
      },
    );

    expect(
      summary.checks.find((check) => check.id === "officials")?.state,
    ).toBe("PASS");
  });
});
`;
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - per-game officials assignment"
echo "  - referee 1 / referee 2"
echo "  - optional linesman 1 / linesman 2"
echo "  - required readiness threshold = two referees assigned"
echo "  - officials feed actual pregame readiness"
echo "  - testing override still affects only effective readiness"
echo "  - unit and readiness integration tests"
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
