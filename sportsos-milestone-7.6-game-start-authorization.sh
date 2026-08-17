#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.6-game-start-authorization"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
AUTH_LIB="apps/dashboard/lib/tournament-game-start-authorization.ts"
AUTH_TEST="apps/dashboard/test/tournament-game-start-authorization-7.6.test.ts"

for file in "$WORKSPACE" "$READINESS_LIB"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'pregameReadinessSummary' "$WORKSPACE" || {
  echo "ERROR: pregame readiness workspace integration not found." >&2
  exit 1
}

grep -Fq 'officialsReady' "$READINESS_LIB" || {
  echo "ERROR: Milestone 7.5 readiness integration not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$AUTH_LIB")" \
  "$BACKUP_DIR/$(dirname "$AUTH_TEST")"

for file in "$WORKSPACE" "$AUTH_LIB" "$AUTH_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$AUTH_LIB" <<'EOF'
export const SPORTSOS_GAME_START_AUTH_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:start-authorization";

export type GameStartAuthorizationMode =
  | "normal"
  | "testing-override";

export type GameStartAuthorizationRecord = {
  gameId: string;
  authorizedAt: string;
  authorizedBy: string;
  mode: GameStartAuthorizationMode;
  actualReadyAtAuthorization: boolean;
  effectiveReadyAtAuthorization: boolean;
  overrideReason: string | null;
};

export type GameStartAuthorizationInput = {
  gameId: string;
  authorizedBy: string;
  actualReady: boolean;
  effectiveReady: boolean;
  testingOverrideEnabled: boolean;
  overrideReason?: string;
  now?: Date;
};

function storageKey(gameId: string): string {
  return `${SPORTSOS_GAME_START_AUTH_STORAGE_PREFIX}:${gameId}`;
}

export function normalizeAuthorizationText(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function canAuthorizeGameStart(
  input: Omit<GameStartAuthorizationInput, "gameId" | "now">,
): boolean {
  const authorizedBy = normalizeAuthorizationText(input.authorizedBy);

  if (!authorizedBy || !input.effectiveReady) {
    return false;
  }

  if (input.actualReady) {
    return true;
  }

  return (
    input.testingOverrideEnabled &&
    normalizeAuthorizationText(input.overrideReason ?? "").length >= 5
  );
}

export function createGameStartAuthorization(
  input: GameStartAuthorizationInput,
): GameStartAuthorizationRecord {
  if (!canAuthorizeGameStart(input)) {
    throw new Error("Game start authorization requirements are not satisfied.");
  }

  const mode: GameStartAuthorizationMode =
    input.actualReady ? "normal" : "testing-override";

  return {
    gameId: input.gameId,
    authorizedAt: (input.now ?? new Date()).toISOString(),
    authorizedBy: normalizeAuthorizationText(input.authorizedBy),
    mode,
    actualReadyAtAuthorization: input.actualReady,
    effectiveReadyAtAuthorization: input.effectiveReady,
    overrideReason:
      mode === "testing-override"
        ? normalizeAuthorizationText(input.overrideReason ?? "")
        : null,
  };
}

export function writeGameStartAuthorization(
  storage: Pick<Storage, "setItem">,
  record: GameStartAuthorizationRecord,
): void {
  storage.setItem(storageKey(record.gameId), JSON.stringify(record));
}

export function readGameStartAuthorization(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): GameStartAuthorizationRecord | null {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as Partial<GameStartAuthorizationRecord>;

    if (
      parsed.gameId !== gameId ||
      typeof parsed.authorizedAt !== "string" ||
      typeof parsed.authorizedBy !== "string" ||
      (parsed.mode !== "normal" &&
        parsed.mode !== "testing-override") ||
      typeof parsed.actualReadyAtAuthorization !== "boolean" ||
      typeof parsed.effectiveReadyAtAuthorization !== "boolean"
    ) {
      return null;
    }

    return {
      gameId,
      authorizedAt: parsed.authorizedAt,
      authorizedBy: normalizeAuthorizationText(parsed.authorizedBy),
      mode: parsed.mode,
      actualReadyAtAuthorization:
        parsed.actualReadyAtAuthorization,
      effectiveReadyAtAuthorization:
        parsed.effectiveReadyAtAuthorization,
      overrideReason:
        parsed.mode === "testing-override"
          ? normalizeAuthorizationText(parsed.overrideReason ?? "")
          : null,
    };
  } catch {
    return null;
  }
}

export function clearGameStartAuthorization(
  storage: Pick<Storage, "removeItem">,
  gameId: string,
): void {
  storage.removeItem(storageKey(gameId));
}
EOF

cat > "$AUTH_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  canAuthorizeGameStart,
  clearGameStartAuthorization,
  createGameStartAuthorization,
  readGameStartAuthorization,
  writeGameStartAuthorization,
} from "../lib/tournament-game-start-authorization";

describe("Milestone 7.6 game start authorization", () => {
  it("authorizes a normally ready game with an operator name", () => {
    expect(
      canAuthorizeGameStart({
        authorizedBy: "Scorekeeper One",
        actualReady: true,
        effectiveReady: true,
        testingOverrideEnabled: false,
      }),
    ).toBe(true);
  });

  it("does not authorize when effective readiness is blocked", () => {
    expect(
      canAuthorizeGameStart({
        authorizedBy: "Scorekeeper One",
        actualReady: false,
        effectiveReady: false,
        testingOverrideEnabled: false,
      }),
    ).toBe(false);
  });

  it("requires a reason when testing override is bypassing actual readiness", () => {
    expect(
      canAuthorizeGameStart({
        authorizedBy: "Tester",
        actualReady: false,
        effectiveReady: true,
        testingOverrideEnabled: true,
        overrideReason: "",
      }),
    ).toBe(false);

    expect(
      canAuthorizeGameStart({
        authorizedBy: "Tester",
        actualReady: false,
        effectiveReady: true,
        testingOverrideEnabled: true,
        overrideReason: "Local feature test",
      }),
    ).toBe(true);
  });

  it("creates a normal authorization snapshot", () => {
    const record = createGameStartAuthorization({
      gameId: "game-76",
      authorizedBy: "  Alex   Operator ",
      actualReady: true,
      effectiveReady: true,
      testingOverrideEnabled: false,
      now: new Date("2026-08-16T22:00:00.000Z"),
    });

    expect(record).toMatchObject({
      gameId: "game-76",
      authorizedBy: "Alex Operator",
      mode: "normal",
      actualReadyAtAuthorization: true,
      effectiveReadyAtAuthorization: true,
      overrideReason: null,
    });
  });

  it("records testing-override authorization without pretending actual readiness passed", () => {
    const record = createGameStartAuthorization({
      gameId: "game-76",
      authorizedBy: "Test Operator",
      actualReady: false,
      effectiveReady: true,
      testingOverrideEnabled: true,
      overrideReason: "Testing unfinished integrations",
      now: new Date("2026-08-16T22:00:00.000Z"),
    });

    expect(record).toMatchObject({
      mode: "testing-override",
      actualReadyAtAuthorization: false,
      effectiveReadyAtAuthorization: true,
      overrideReason: "Testing unfinished integrations",
    });
  });

  it("persists, restores, and clears an authorization", () => {
    const values = new Map<string, string>();

    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
      removeItem: (key: string) => {
        values.delete(key);
      },
    };

    const record = createGameStartAuthorization({
      gameId: "game-76",
      authorizedBy: "Operator",
      actualReady: true,
      effectiveReady: true,
      testingOverrideEnabled: false,
      now: new Date("2026-08-16T22:00:00.000Z"),
    });

    writeGameStartAuthorization(storage, record);
    expect(readGameStartAuthorization(storage, "game-76")).toEqual(record);

    clearGameStartAuthorization(storage, "game-76");
    expect(readGameStartAuthorization(storage, "game-76")).toBeNull();
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function assertFound(condition, message) {
  if (!condition) throw new Error(message);
}

if (!text.includes('from "../../lib/tournament-game-start-authorization";')) {
  const lastLibImport =
`} from "../../lib/tournament-officials-assignment";`;

  assertFound(
    text.includes(lastLibImport),
    "Could not locate officials-assignment import.",
  );

  text = text.replace(
    lastLibImport,
`${lastLibImport}
import {
  canAuthorizeGameStart,
  clearGameStartAuthorization,
  createGameStartAuthorization,
  readGameStartAuthorization,
  writeGameStartAuthorization,
  type GameStartAuthorizationRecord,
} from "../../lib/tournament-game-start-authorization";`,
  );
}

if (!text.includes("const [gameStartAuthorization")) {
  const componentMatch = text.match(
    /export function TournamentGameOperationsWorkspace[^{]*\{/
  );

  assertFound(
    componentMatch,
    "Could not locate TournamentGameOperationsWorkspace function.",
  );

  const insertionPoint =
    componentMatch.index + componentMatch[0].length;

  const state = `
  const [gameStartAuthorization, setGameStartAuthorization] =
    useState<GameStartAuthorizationRecord | null>(null);
  const [authorizationOperator, setAuthorizationOperator] = useState("");
  const [authorizationOverrideReason, setAuthorizationOverrideReason] =
    useState("");
`;

  text =
    text.slice(0, insertionPoint) +
    state +
    text.slice(insertionPoint);
}

if (!text.includes("readGameStartAuthorization(window.localStorage")) {
  const readinessMemoIndex = text.indexOf(
    "const pregameReadinessSummary = useMemo("
  );

  assertFound(
    readinessMemoIndex >= 0,
    "Could not locate pregame readiness memo.",
  );

  const effect = `  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setGameStartAuthorization(null);
      setAuthorizationOperator("");
      setAuthorizationOverrideReason("");
      return;
    }

    const existing = readGameStartAuthorization(
      window.localStorage,
      selectedGame.id,
    );

    setGameStartAuthorization(existing);
    setAuthorizationOperator(existing?.authorizedBy ?? "");
    setAuthorizationOverrideReason(
      existing?.overrideReason ?? "",
    );
  }, [selectedGame]);

`;

  text =
    text.slice(0, readinessMemoIndex) +
    effect +
    text.slice(readinessMemoIndex);
}

if (!text.includes("const authorizeGameStart")) {
  const toggleIndex = text.indexOf("const toggleTestingOverride");

  assertFound(
    toggleIndex >= 0,
    "Could not locate testing override toggle.",
  );

  const functions = `  const authorizeGameStart = () => {
    if (
      !selectedGame ||
      !pregameReadinessSummary ||
      typeof window === "undefined"
    ) {
      return;
    }

    const record = createGameStartAuthorization({
      gameId: selectedGame.id,
      authorizedBy: authorizationOperator,
      actualReady: pregameReadinessSummary.actualReady,
      effectiveReady: pregameReadinessSummary.effectiveReady,
      testingOverrideEnabled,
      overrideReason: authorizationOverrideReason,
    });

    writeGameStartAuthorization(
      window.localStorage,
      record,
    );

    setGameStartAuthorization(record);
  };

  const revokeGameStartAuthorization = () => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    clearGameStartAuthorization(
      window.localStorage,
      selectedGame.id,
    );

    setGameStartAuthorization(null);
  };

`;

  text =
    text.slice(0, toggleIndex) +
    functions +
    text.slice(toggleIndex);
}

if (!text.includes('data-testid="game-start-authorization-panel"')) {
  const readinessHeadingIndex = text.indexOf("Pregame readiness");

  assertFound(
    readinessHeadingIndex >= 0,
    "Could not locate Pregame readiness panel.",
  );

  const readinessAsideIndex = text.lastIndexOf(
    '<aside className="rounded-xl',
    readinessHeadingIndex,
  );

  assertFound(
    readinessAsideIndex >= 0,
    "Could not locate Pregame readiness aside.",
  );

  const panel = `            <section
              data-testid="game-start-authorization-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Game start authorization
                  </h2>
                  <p className="mt-1 text-xs leading-5 text-slate-500">
                    Record operator approval after readiness review. This
                    authorization does not itself transition the game to LIVE.
                  </p>
                </div>

                <span
                  data-testid="game-start-authorization-status"
                  className={
                    gameStartAuthorization
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {gameStartAuthorization
                    ? "Authorized"
                    : "Not authorized"}
                </span>
              </div>

              {gameStartAuthorization ? (
                <div className="mt-4 rounded-lg border border-emerald-900/70 bg-emerald-950/20 p-4">
                  <div className="grid gap-2 text-sm md:grid-cols-2">
                    <div>
                      <span className="text-slate-500">Authorized by</span>
                      <div className="font-semibold text-slate-200">
                        {gameStartAuthorization.authorizedBy}
                      </div>
                    </div>
                    <div>
                      <span className="text-slate-500">Mode</span>
                      <div className="font-semibold text-slate-200">
                        {gameStartAuthorization.mode === "normal"
                          ? "Normal readiness"
                          : "Testing override"}
                      </div>
                    </div>
                  </div>

                  {gameStartAuthorization.mode === "testing-override" ? (
                    <div className="mt-3 rounded-lg border border-amber-800/60 bg-amber-950/20 px-3 py-2 text-xs text-amber-300">
                      Actual readiness was BLOCKED when authorization was
                      recorded. Reason:{" "}
                      {gameStartAuthorization.overrideReason}
                    </div>
                  ) : null}

                  <button
                    type="button"
                    data-testid="revoke-game-start-authorization"
                    onClick={revokeGameStartAuthorization}
                    className="mt-4 rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900"
                  >
                    Revoke authorization
                  </button>
                </div>
              ) : (
                <div className="mt-4 space-y-3">
                  <label className="block">
                    <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                      Authorizing operator
                    </span>
                    <input
                      type="text"
                      data-testid="game-start-authorization-operator"
                      value={authorizationOperator}
                      onChange={(event) =>
                        setAuthorizationOperator(event.target.value)
                      }
                      placeholder="Operator name"
                      className="mt-2 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-slate-500"
                    />
                  </label>

                  {!pregameReadinessSummary?.actualReady &&
                  testingOverrideEnabled ? (
                    <label className="block">
                      <span className="text-xs font-semibold uppercase tracking-wide text-amber-400">
                        Testing override reason
                      </span>
                      <input
                        type="text"
                        data-testid="game-start-authorization-override-reason"
                        value={authorizationOverrideReason}
                        onChange={(event) =>
                          setAuthorizationOverrideReason(event.target.value)
                        }
                        placeholder="Why is the readiness gate being bypassed?"
                        className="mt-2 w-full rounded-lg border border-amber-800/60 bg-slate-950 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-amber-500"
                      />
                    </label>
                  ) : null}

                  <button
                    type="button"
                    data-testid="authorize-game-start"
                    disabled={
                      !pregameReadinessSummary ||
                      !canAuthorizeGameStart({
                        authorizedBy: authorizationOperator,
                        actualReady:
                          pregameReadinessSummary.actualReady,
                        effectiveReady:
                          pregameReadinessSummary.effectiveReady,
                        testingOverrideEnabled,
                        overrideReason:
                          authorizationOverrideReason,
                      })
                    }
                    onClick={authorizeGameStart}
                    className="w-full rounded-lg border border-emerald-800/70 bg-emerald-950/20 px-3 py-2 text-sm font-semibold text-emerald-300 transition hover:border-emerald-600 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Authorize game start
                  </button>
                </div>
              )}

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Security boundary: this browser-side authorization is an
                operations record only. Milestone 7.7 will require an
                authenticated server-side transition before a game can become
                LIVE; local testing override state will never be accepted as
                server authority.
              </p>
            </section>

`;

  text =
    text.slice(0, readinessAsideIndex) +
    panel +
    text.slice(readinessAsideIndex);
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - per-game game-start authorization record"
echo "  - authorizing operator"
echo "  - readiness snapshot at authorization time"
echo "  - explicit testing-override authorization mode"
echo "  - required override reason when actual readiness is blocked"
echo "  - revoke authorization"
echo "  - automated 7.6 unit tests"
echo
echo "Security boundary:"
echo "  - this milestone DOES NOT transition a game to LIVE"
echo "  - localStorage/testing override is NOT server authority"
echo "  - actual LIVE transition will be authenticated/server-side in 7.7"
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
