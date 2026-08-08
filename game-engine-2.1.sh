#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

REPO="apps/api/src/modules/games/repository.ts"
ENGINE="apps/api/src/modules/games/engine.ts"
TEST="apps/api/test/game-engine.test.ts"

for cmd in bash awk sed grep cp date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

for f in "$REPO" "apps/api/src/modules/games/schemas.ts"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${REPO}.bak-game-engine-2.1-${STAMP}"
cp "$REPO" "$BACKUP"

cat > "$ENGINE" <<'EOF'
import type { ScoreAction } from "./schemas.js";
import type { GamePhase, GameStatus } from "./types.js";

export class GamePhaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GamePhaseError";
  }
}

export interface GameEngineState {
  homeScore: number;
  awayScore: number;
  status: GameStatus;
  gamePhase: GamePhase;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: Date | null;
  regulationPeriods: number;
  regulationPeriodLengthMs: number;
  intermissionLengthMs: number;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: Date | null;
  overtimeEnabled: boolean;
  overtimeLengthMs: number;
}

export interface GameEngineTransition {
  state: GameEngineState;
  penaltyClockAdjustmentMs: number;
}

function copyDate(value: Date): Date {
  return new Date(value.getTime());
}

export function applyGameEngineAction(
  current: Readonly<GameEngineState>,
  action: ScoreAction,
  now = new Date(),
): GameEngineTransition {
  const state: GameEngineState = {
    ...current,
    clockStartedAt: current.clockStartedAt ? copyDate(current.clockStartedAt) : null,
    intermissionStartedAt: current.intermissionStartedAt
      ? copyDate(current.intermissionStartedAt)
      : null,
  };

  const previousClockRemainingMs = state.clockRemainingMs;

  switch (action.action) {
    case "adjustScore":
      if (action.side === "home") {
        state.homeScore = Math.max(0, Math.min(999, state.homeScore + action.amount));
      } else {
        state.awayScore = Math.max(0, Math.min(999, state.awayScore + action.amount));
      }
      break;

    case "setScore":
      state.homeScore = action.homeScore;
      state.awayScore = action.awayScore;
      break;

    case "startClock":
      if (state.status === "FINAL") {
        throw new GamePhaseError("A final game cannot be restarted");
      }
      if (state.gamePhase === "INTERMISSION") {
        throw new GamePhaseError(
          "Finish or skip intermission before starting the game clock",
        );
      }
      if (state.clockRemainingMs > 0) {
        state.clockRunning = true;
        state.clockStartedAt = copyDate(now);
        if (state.status === "SCHEDULED") state.status = "LIVE";
        if (state.gamePhase === "PREGAME") state.gamePhase = "REGULATION";
      }
      break;

    case "pauseClock":
      state.clockRunning = false;
      state.clockStartedAt = null;
      break;

    case "startIntermission":
      if (state.status === "FINAL") {
        throw new GamePhaseError("Intermission cannot start after the game is final");
      }
      if (state.clockRemainingMs > 0) {
        throw new GamePhaseError(
          "Intermission can start only when the game clock is at 0:00",
        );
      }
      state.clockRunning = false;
      state.clockStartedAt = null;
      if (state.intermissionRemainingMs <= 0) {
        state.intermissionRemainingMs = state.intermissionLengthMs;
      }
      state.intermissionRunning = state.intermissionRemainingMs > 0;
      state.intermissionStartedAt = state.intermissionRunning ? copyDate(now) : null;
      if (state.intermissionRemainingMs > 0) state.gamePhase = "INTERMISSION";
      break;

    case "pauseIntermission":
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      break;

    case "resetIntermission":
      state.intermissionRemainingMs = state.intermissionLengthMs;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      break;

    case "setIntermission":
      state.intermissionLengthMs = action.intermissionLengthMs;
      state.intermissionRemainingMs = action.intermissionLengthMs;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      break;

    case "skipIntermission":
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase =
        state.period > state.regulationPeriods ? "OVERTIME" : "REGULATION";
      break;

    case "nextPeriod":
      state.clockRunning = false;
      state.clockStartedAt = null;

      if (state.status === "FINAL") {
        throw new GamePhaseError("A final game cannot advance to another period");
      }
      if (state.clockRemainingMs > 0) {
        throw new GamePhaseError(
          "The game clock must be at 0:00 before advancing periods",
        );
      }
      if (state.gamePhase === "INTERMISSION" && state.intermissionRemainingMs > 0) {
        throw new GamePhaseError(
          "Finish or skip intermission before advancing periods",
        );
      }
      if (state.period >= state.regulationPeriods) {
        throw new GamePhaseError(
          "Choose overtime or final after regulation has ended",
        );
      }

      state.period += 1;
      state.periodLengthMs = current.periodLengthMs;
      state.clockRemainingMs = state.periodLengthMs;
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase = "REGULATION";
      break;

    case "startOvertime":
      state.clockRunning = false;
      state.clockStartedAt = null;

      if (state.status === "FINAL") {
        throw new GamePhaseError("A final game cannot enter overtime");
      }
      if (!state.overtimeEnabled) {
        throw new GamePhaseError("Overtime is disabled for this game");
      }
      if (state.period < state.regulationPeriods) {
        throw new GamePhaseError("Regulation has not ended");
      }
      if (state.clockRemainingMs > 0) {
        throw new GamePhaseError("Regulation must reach 0:00 before overtime");
      }
      if (state.gamePhase === "INTERMISSION" && state.intermissionRemainingMs > 0) {
        throw new GamePhaseError(
          "Finish or skip intermission before starting overtime",
        );
      }

      state.period = Math.max(state.period + 1, state.regulationPeriods + 1);
      state.periodLengthMs = state.overtimeLengthMs;
      state.clockRemainingMs = state.overtimeLengthMs;
      state.clockRunning = false;
      state.clockStartedAt = null;
      state.status = "LIVE";
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase = "OVERTIME";
      break;

    case "finishGame":
      state.clockRunning = false;
      state.clockStartedAt = null;
      state.clockRemainingMs = 0;
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.status = "FINAL";
      state.gamePhase = "FINAL";
      break;

    case "resetClock":
      state.periodLengthMs = action.periodLengthMs ?? state.periodLengthMs;
      state.clockRemainingMs = state.periodLengthMs;
      state.clockRunning = false;
      state.clockStartedAt = null;
      break;

    case "adjustClock":
      state.clockRemainingMs = Math.max(
        0,
        Math.min(7_200_000, state.clockRemainingMs + action.amountMs),
      );
      state.clockRunning = state.clockRunning && state.clockRemainingMs > 0;
      state.clockStartedAt = state.clockRunning ? copyDate(now) : null;
      break;

    case "setClock":
      state.clockRemainingMs = action.clockRemainingMs;
      state.periodLengthMs = action.clockRemainingMs;
      state.clockRunning = false;
      state.clockStartedAt = null;
      break;

    case "setPeriod":
      state.period = action.period;
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase =
        state.period > state.regulationPeriods ? "OVERTIME" : "REGULATION";
      state.clockStartedAt = state.clockRunning ? copyDate(now) : null;
      break;

    case "setStatus":
      state.status = action.status;

      if (state.status !== "LIVE") {
        state.clockRunning = false;
        state.clockStartedAt = null;
        state.intermissionRunning = false;
        state.intermissionStartedAt = null;
      }

      if (state.status === "FINAL") {
        state.clockRemainingMs = 0;
        state.intermissionRemainingMs = 0;
        state.gamePhase = "FINAL";
      } else if (state.status === "SCHEDULED") {
        state.gamePhase = "PREGAME";
      } else if (state.status === "LIVE" && state.gamePhase === "PREGAME") {
        state.gamePhase =
          state.period > state.regulationPeriods ? "OVERTIME" : "REGULATION";
      }
      break;
  }

  if (state.clockRemainingMs === 0) {
    state.clockRunning = false;
    state.clockStartedAt = null;
  }

  const penaltyClockAdjustmentMs =
    action.action === "adjustClock" ||
    action.action === "setClock" ||
    action.action === "resetClock"
      ? state.clockRemainingMs - previousClockRemainingMs
      : 0;

  return { state, penaltyClockAdjustmentMs };
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  applyGameEngineAction,
  GamePhaseError,
  type GameEngineState,
} from "../src/modules/games/engine.js";

function state(overrides: Partial<GameEngineState> = {}): GameEngineState {
  return {
    homeScore: 0,
    awayScore: 0,
    status: "SCHEDULED",
    gamePhase: "PREGAME",
    period: 1,
    periodLengthMs: 900_000,
    clockRemainingMs: 900_000,
    clockRunning: false,
    clockStartedAt: null,
    regulationPeriods: 3,
    regulationPeriodLengthMs: 900_000,
    intermissionLengthMs: 600_000,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    overtimeEnabled: true,
    overtimeLengthMs: 300_000,
    ...overrides,
  };
}

describe("authoritative game engine", () => {
  it("starts a scheduled game in regulation", () => {
    const now = new Date("2026-08-08T13:00:00.000Z");
    const result = applyGameEngineAction(state(), { action: "startClock" }, now);

    expect(result.state.status).toBe("LIVE");
    expect(result.state.gamePhase).toBe("REGULATION");
    expect(result.state.clockRunning).toBe(true);
    expect(result.state.clockStartedAt).toEqual(now);
  });

  it("runs regulation period handoff through intermission", () => {
    const ended = state({
      status: "LIVE",
      gamePhase: "REGULATION",
      period: 1,
      clockRemainingMs: 0,
    });

    const intermission = applyGameEngineAction(ended, {
      action: "startIntermission",
    }).state;

    expect(intermission.gamePhase).toBe("INTERMISSION");
    expect(intermission.intermissionRemainingMs).toBe(600_000);
    expect(intermission.intermissionRunning).toBe(true);

    const completed = {
      ...intermission,
      intermissionRemainingMs: 0,
      intermissionRunning: false,
      intermissionStartedAt: null,
    };

    const periodTwo = applyGameEngineAction(completed, {
      action: "nextPeriod",
    }).state;

    expect(periodTwo.period).toBe(2);
    expect(periodTwo.gamePhase).toBe("REGULATION");
    expect(periodTwo.clockRemainingMs).toBe(900_000);
    expect(periodTwo.clockRunning).toBe(false);
  });

  it("requires an explicit overtime or final decision after regulation", () => {
    const endedRegulation = state({
      status: "LIVE",
      gamePhase: "REGULATION",
      period: 3,
      clockRemainingMs: 0,
    });

    expect(() =>
      applyGameEngineAction(endedRegulation, { action: "nextPeriod" }),
    ).toThrow("Choose overtime or final after regulation has ended");
  });

  it("enters configured overtime after regulation", () => {
    const endedRegulation = state({
      status: "LIVE",
      gamePhase: "REGULATION",
      period: 3,
      clockRemainingMs: 0,
      overtimeLengthMs: 240_000,
    });

    const overtime = applyGameEngineAction(endedRegulation, {
      action: "startOvertime",
    }).state;

    expect(overtime.status).toBe("LIVE");
    expect(overtime.gamePhase).toBe("OVERTIME");
    expect(overtime.period).toBe(4);
    expect(overtime.periodLengthMs).toBe(240_000);
    expect(overtime.clockRemainingMs).toBe(240_000);
    expect(overtime.clockRunning).toBe(false);
  });

  it("finishes a game and stops every game timer", () => {
    const final = applyGameEngineAction(
      state({
        status: "LIVE",
        gamePhase: "OVERTIME",
        period: 4,
        clockRemainingMs: 100_000,
        clockRunning: true,
        clockStartedAt: new Date(),
        intermissionRemainingMs: 50_000,
        intermissionRunning: true,
        intermissionStartedAt: new Date(),
      }),
      { action: "finishGame" },
    ).state;

    expect(final.status).toBe("FINAL");
    expect(final.gamePhase).toBe("FINAL");
    expect(final.clockRemainingMs).toBe(0);
    expect(final.clockRunning).toBe(false);
    expect(final.intermissionRemainingMs).toBe(0);
    expect(final.intermissionRunning).toBe(false);
  });

  it("rejects clock start during intermission", () => {
    expect(() =>
      applyGameEngineAction(
        state({
          status: "LIVE",
          gamePhase: "INTERMISSION",
          intermissionRemainingMs: 120_000,
        }),
        { action: "startClock" },
      ),
    ).toThrow(GamePhaseError);
  });

  it("returns penalty-clock delta for manual game-clock corrections", () => {
    const result = applyGameEngineAction(
      state({
        status: "LIVE",
        gamePhase: "REGULATION",
        clockRemainingMs: 300_000,
      }),
      { action: "adjustClock", amountMs: 30_000 },
    );

    expect(result.state.clockRemainingMs).toBe(330_000);
    expect(result.penaltyClockAdjustmentMs).toBe(30_000);
  });

  it("does not mutate its input state", () => {
    const original = state();
    const before = structuredClone(original);

    applyGameEngineAction(original, { action: "startClock" });

    expect(original).toEqual(before);
  });
});
EOF

TMP="${REPO}.tmp-game-engine-2.1-${STAMP}"

awk '
BEGIN {
  import_done = 0
  class_skip = 0
  mutation_skip = 0
  mutation_done = 0
}
{
  line = $0

  if (!import_done && line == "import type { Game, GamePhase, GameStatus, GameTeamOption } from \"./types.js\";") {
    print line
    print "import {"
    print "  applyGameEngineAction,"
    print "  type GameEngineState,"
    print "} from \"./engine.js\";"
    print "export { GamePhaseError } from \"./engine.js\";"
    import_done = 1
    next
  }

  if (!class_skip && line == "export class GamePhaseError extends Error {") {
    class_skip = 1
    next
  }

  if (class_skip) {
    if (line == "}") {
      class_skip = 0
      getline
      print ""
    }
    next
  }

  if (!mutation_done && line == "    let homeScore = Number(row.home_score);") {
    mutation_skip = 1

    print "    const clockRemainingMsAtAction = materializedRemainingMs(row);"
    print "    const intermissionRemainingMsAtAction = effectiveIntermissionRemainingMs("
    print "      Number(row.intermission_remaining_ms ?? 0),"
    print "      Boolean(row.intermission_running),"
    print "      row.intermission_started_at,"
    print "    );"
    print ""
    print "    const engineState: GameEngineState = {"
    print "      homeScore: Number(row.home_score),"
    print "      awayScore: Number(row.away_score),"
    print "      status: row.status,"
    print "      gamePhase: row.game_phase ?? (row.status === \"FINAL\" ? \"FINAL\" : \"PREGAME\"),"
    print "      period: Number(row.period),"
    print "      periodLengthMs: Number(row.period_length_ms),"
    print "      clockRemainingMs: clockRemainingMsAtAction,"
    print "      clockRunning: Boolean(row.clock_running) && clockRemainingMsAtAction > 0,"
    print "      clockStartedAt:"
    print "        Boolean(row.clock_running) && clockRemainingMsAtAction > 0"
    print "          ? new Date()"
    print "          : null,"
    print "      regulationPeriods: Number(row.regulation_periods ?? 3),"
    print "      regulationPeriodLengthMs: Number("
    print "        row.regulation_period_length_ms ?? row.period_length_ms,"
    print "      ),"
    print "      intermissionLengthMs: Number(row.intermission_length_ms ?? 0),"
    print "      intermissionRemainingMs: intermissionRemainingMsAtAction,"
    print "      intermissionRunning:"
    print "        Boolean(row.intermission_running) && intermissionRemainingMsAtAction > 0,"
    print "      intermissionStartedAt:"
    print "        Boolean(row.intermission_running) && intermissionRemainingMsAtAction > 0"
    print "          ? new Date()"
    print "          : null,"
    print "      overtimeEnabled: Boolean(row.overtime_enabled),"
    print "      overtimeLengthMs: Number(row.overtime_length_ms ?? 300_000),"
    print "    };"
    print ""
    print "    await materializePenaltyClocks(connection, id);"
    print ""
    print "    const transition = applyGameEngineAction(engineState, action);"
    print "    const {"
    print "      homeScore,"
    print "      awayScore,"
    print "      status,"
    print "      gamePhase,"
    print "      period,"
    print "      periodLengthMs,"
    print "      clockRemainingMs,"
    print "      clockRunning,"
    print "      clockStartedAt,"
    print "      intermissionLengthMs,"
    print "      intermissionRemainingMs,"
    print "      intermissionRunning,"
    print "      intermissionStartedAt,"
    print "    } = transition.state;"
    print ""
    print "    await adjustActivePenaltyClocks("
    print "      connection,"
    print "      id,"
    print "      transition.penaltyClockAdjustmentMs,"
    print "    );"
    next
  }

  if (mutation_skip) {
    if (line == "    await adjustActivePenaltyClocks(connection, id, penaltyClockAdjustmentMs);") {
      mutation_skip = 0
      mutation_done = 1
    }
    next
  }

  print line
}
END {
  if (!import_done) {
    print "ERROR: expected import marker not found" > "/dev/stderr"
    exit 21
  }
  if (class_skip) {
    print "ERROR: GamePhaseError class block did not terminate" > "/dev/stderr"
    exit 22
  }
  if (!mutation_done) {
    print "ERROR: scoring mutation block markers not found" > "/dev/stderr"
    exit 23
  }
}
' "$REPO" > "$TMP"

mv "$TMP" "$REPO"

echo
echo "============================================="
echo " SportsOS Next - Game Engine 2.1"
echo "============================================="
echo "Applied successfully."
echo
echo "Created:"
echo "  $ENGINE"
echo "  $TEST"
echo
echo "Modified:"
echo "  $REPO"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Next run:"
echo "  npm run typecheck"
echo "  npm test"
