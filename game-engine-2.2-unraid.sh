#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

for cmd in bash node npm cp date grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

ENGINE="apps/api/src/modules/games/engine.ts"
REPO="apps/api/src/modules/games/repository.ts"
ROUTES="apps/api/src/modules/games/routes.ts"
CLOCK="apps/api/src/modules/games/clock-expiration.ts"
APP="apps/api/src/app.ts"
FLOW_TEST="apps/api/test/game-flow-regression.test.ts"
LIFECYCLE="apps/api/src/modules/games/lifecycle.ts"
LIFECYCLE_TEST="apps/api/test/game-lifecycle.test.ts"
RECOVERY_TEST="apps/api/test/game-recovery.test.ts"

for f in "$ENGINE" "$REPO" "$ROUTES" "$CLOCK" "$APP" "$FLOW_TEST"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'applyGameEngineAction' "$ENGINE"; then
  echo "Game Engine 2.1 was not detected in $ENGINE" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/2.2-${STAMP}"
mkdir -p "$BACKUP_DIR"

for f in "$ENGINE" "$REPO" "$ROUTES" "$CLOCK" "$APP" "$FLOW_TEST"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

cat > "$LIFECYCLE" <<'EOF'
import { z } from "zod";
import type { ScoreAction } from "./schemas.js";
import type { Game } from "./types.js";

export const gameLifecycleCommands = [
  "startGame",
  "endPeriod",
  "beginIntermission",
  "startNextPeriod",
  "startOvertime",
  "finishGame",
] as const;

export type GameLifecycleCommand = (typeof gameLifecycleCommands)[number];

export const gameLifecycleCommandSchema = z.object({
  command: z.enum(gameLifecycleCommands),
  commandId: z
    .string()
    .regex(/^[A-Za-z0-9._:-]{8,80}$/)
    .optional(),
});

export class GameLifecycleError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GameLifecycleError";
  }
}

type LifecycleGame = Pick<
  Game,
  | "status"
  | "gamePhase"
  | "period"
  | "regulationPeriods"
  | "clockRemainingMs"
>;

export function resolveLifecycleAction(
  game: LifecycleGame,
  command: GameLifecycleCommand,
): ScoreAction {
  switch (command) {
    case "startGame":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError("A final game cannot be restarted");
      }
      if (game.gamePhase !== "PREGAME") {
        throw new GameLifecycleError("The game has already started");
      }
      return { action: "startClock" };

    case "endPeriod":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError("A final game has no active period");
      }
      if (game.gamePhase === "INTERMISSION") {
        throw new GameLifecycleError("The game is already in intermission");
      }
      if (game.clockRemainingMs > 0) {
        throw new GameLifecycleError(
          "The game clock must be at 0:00 before ending the period",
        );
      }

      // For regulation periods before the last period, ending the period enters
      // intermission. At the end of regulation we intentionally leave the game
      // at 0:00 so the scorer must explicitly choose overtime or final.
      if (
        game.gamePhase === "REGULATION" &&
        game.period < game.regulationPeriods
      ) {
        return { action: "startIntermission" };
      }

      return { action: "pauseClock" };

    case "beginIntermission":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError(
          "Intermission cannot start after the game is final",
        );
      }
      if (game.gamePhase === "INTERMISSION") {
        throw new GameLifecycleError("The game is already in intermission");
      }
      if (game.clockRemainingMs > 0) {
        throw new GameLifecycleError(
          "Intermission can start only when the game clock is at 0:00",
        );
      }
      return { action: "startIntermission" };

    case "startNextPeriod":
      return { action: "nextPeriod" };

    case "startOvertime":
      return { action: "startOvertime" };

    case "finishGame":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError("The game is already final");
      }
      return { action: "finishGame" };
  }
}
EOF

cat > "$LIFECYCLE_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  GameLifecycleError,
  resolveLifecycleAction,
} from "../src/modules/games/lifecycle.js";

function game(
  overrides: Partial<{
    status: "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
    gamePhase: "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";
    period: number;
    regulationPeriods: number;
    clockRemainingMs: number;
  }> = {},
) {
  return {
    status: "LIVE" as const,
    gamePhase: "REGULATION" as const,
    period: 1,
    regulationPeriods: 3,
    clockRemainingMs: 0,
    ...overrides,
  };
}

describe("game lifecycle command resolution", () => {
  it("starts a pregame through the authoritative clock action", () => {
    expect(
      resolveLifecycleAction(
        game({ status: "SCHEDULED", gamePhase: "PREGAME", clockRemainingMs: 900_000 }),
        "startGame",
      ),
    ).toEqual({ action: "startClock" });
  });

  it("ends an early regulation period by beginning intermission", () => {
    expect(resolveLifecycleAction(game({ period: 1 }), "endPeriod")).toEqual({
      action: "startIntermission",
    });
  });

  it("leaves final regulation at zero for an explicit overtime/final decision", () => {
    expect(
      resolveLifecycleAction(
        game({ period: 3, regulationPeriods: 3 }),
        "endPeriod",
      ),
    ).toEqual({ action: "pauseClock" });
  });

  it("rejects ending a period while time remains", () => {
    expect(() =>
      resolveLifecycleAction(game({ clockRemainingMs: 15_000 }), "endPeriod"),
    ).toThrow("The game clock must be at 0:00 before ending the period");
  });

  it("maps next-period, overtime, and finish commands explicitly", () => {
    expect(resolveLifecycleAction(game(), "startNextPeriod")).toEqual({
      action: "nextPeriod",
    });
    expect(resolveLifecycleAction(game({ period: 3 }), "startOvertime")).toEqual({
      action: "startOvertime",
    });
    expect(resolveLifecycleAction(game(), "finishGame")).toEqual({
      action: "finishGame",
    });
  });

  it("rejects lifecycle changes after final", () => {
    expect(() =>
      resolveLifecycleAction(
        game({ status: "FINAL", gamePhase: "FINAL" }),
        "startGame",
      ),
    ).toThrow(GameLifecycleError);
  });
});
EOF

cat > "$RECOVERY_TEST" <<'EOF'
import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const connectionExecute = vi.fn();
const beginTransaction = vi.fn();
const commit = vi.fn();
const rollback = vi.fn();
const release = vi.fn();
const materializePenaltyClocks = vi.fn();
const enqueueRealtimeEvent = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
    getConnection: vi.fn(async () => ({
      execute: connectionExecute,
      beginTransaction,
      commit,
      rollback,
      release,
    })),
  },
}));

vi.mock("../src/infrastructure/realtime-outbox.js", () => ({
  enqueueRealtimeEvent,
}));

vi.mock("../src/modules/penalties/repository.js", () => ({
  materializePenaltyClocks,
}));

const { recoverGameClocksOnStartup } = await import(
  "../src/modules/games/clock-expiration.js"
);

function candidate(
  id: number,
  overrides: Record<string, unknown> = {},
) {
  return {
    id,
    organization_id: 8,
    clock_remaining_ms: 1_000,
    clock_running: 1,
    clock_started_at: new Date(0),
    intermission_remaining_ms: 0,
    intermission_running: 0,
    intermission_started_at: null,
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  beginTransaction.mockResolvedValue(undefined);
  commit.mockResolvedValue(undefined);
  rollback.mockResolvedValue(undefined);
  release.mockReturnValue(undefined);
  materializePenaltyClocks.mockResolvedValue(undefined);
  enqueueRealtimeEvent.mockResolvedValue(undefined);
});

describe("startup game-clock recovery", () => {
  it("recovers multiple expired games independently", async () => {
    const regulation = candidate(11);
    const overtime = candidate(12);
    const rows = [regulation, overtime];

    poolExecute.mockResolvedValueOnce([rows]);

    let lock = 0;
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("FROM games") && sql.includes("FOR UPDATE")) {
        return [[rows[lock++]]];
      }
      return [{ affectedRows: 1 }];
    });

    await expect(recoverGameClocksOnStartup(5_000)).resolves.toBe(2);

    expect(materializePenaltyClocks).toHaveBeenCalledTimes(2);
    expect(commit).toHaveBeenCalledTimes(2);
    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:11",
        event: "game:clock-expired",
      }),
    );
    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:12",
        event: "game:clock-expired",
      }),
    );
  });

  it("recovers an expired intermission without touching penalty clocks", async () => {
    const row = candidate(21, {
      clock_remaining_ms: 0,
      clock_running: 0,
      clock_started_at: null,
      intermission_remaining_ms: 1_000,
      intermission_running: 1,
      intermission_started_at: new Date(0),
    });

    poolExecute.mockResolvedValueOnce([[row]]);
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("FROM games") && sql.includes("FOR UPDATE")) {
        return [[row]];
      }
      return [{ affectedRows: 1 }];
    });

    await expect(recoverGameClocksOnStartup(5_000)).resolves.toBe(1);
    expect(materializePenaltyClocks).not.toHaveBeenCalled();
    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:21",
        event: "game:intermission-expired",
      }),
    );
  });

  it("leaves still-running clocks persisted for timestamp-based reconstruction", async () => {
    const row = candidate(31, {
      clock_remaining_ms: 60_000,
      clock_started_at: new Date(4_000),
    });

    poolExecute.mockResolvedValueOnce([[row]]);

    await expect(recoverGameClocksOnStartup(5_000)).resolves.toBe(0);
    expect(connectionExecute).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
  });
});
EOF

node <<'NODE'
const fs = require("fs");

function read(path) {
  return fs.readFileSync(path, "utf8");
}
function write(path, text) {
  fs.writeFileSync(path, text);
}
function replaceOnce(path, oldText, newText, label) {
  const text = read(path);
  const count = text.split(oldText).length - 1;
  if (count !== 1) {
    throw new Error(`${label}: expected exactly one match in ${path}, found ${count}`);
  }
  write(path, text.replace(oldText, newText));
}

// 1) Separate current clock correction from configured period duration.
replaceOnce(
  "apps/api/src/modules/games/engine.ts",
`      state.period += 1;
      state.periodLengthMs = current.periodLengthMs;
      state.clockRemainingMs = state.periodLengthMs;`,
`      state.period += 1;
      state.periodLengthMs = state.regulationPeriodLengthMs;
      state.clockRemainingMs = state.regulationPeriodLengthMs;`,
  "next-period configured length",
);

replaceOnce(
  "apps/api/src/modules/games/engine.ts",
`    case "setClock":
      state.clockRemainingMs = action.clockRemainingMs;
      state.periodLengthMs = action.clockRemainingMs;
      state.clockRunning = false;`,
`    case "setClock":
      // A scorer correction changes only the current clock. It must not change
      // the configured duration used by future regulation periods.
      state.clockRemainingMs = action.clockRemainingMs;
      state.clockRunning = false;`,
  "setClock separation",
);

// 2) Existing regression intended a 12-minute configured regulation period.
// Make that explicit now that period configuration is separate from clock correction.
replaceOnce(
  "apps/api/test/game-flow-regression.test.ts",
`        period: 1,
        period_length_ms: 720_000,
        intermission_remaining_ms: 0,`,
`        period: 1,
        period_length_ms: 720_000,
        regulation_period_length_ms: 720_000,
        intermission_remaining_ms: 0,`,
  "regulation length regression fixture",
);

// 3) Give startup recovery an explicit semantic API.
const clockPath = "apps/api/src/modules/games/clock-expiration.ts";
let clock = read(clockPath);
const marker = `export function startClockExpirationService(`;
if (!clock.includes(marker)) {
  throw new Error("clock recovery insertion marker not found");
}
clock = clock.replace(
  marker,
`/**
 * Reconcile persisted timers before the API becomes ready.
 *
 * Expired clocks are materialized transactionally. Clocks that still have time
 * remaining stay persisted with their original started_at timestamp, allowing
 * every reader to reconstruct the authoritative remaining time after restart.
 */
export async function recoverGameClocksOnStartup(
  nowMs = Date.now(),
): Promise<number> {
  return processExpiredGameClocks(nowMs);
}

${marker}`,
);
write(clockPath, clock);

// 4) Reconcile persisted clocks before Fastify reports ready.
replaceOnce(
  "apps/api/src/app.ts",
`import { startClockExpirationService } from "./modules/games/clock-expiration.js";`,
`import {
  recoverGameClocksOnStartup,
  startClockExpirationService,
} from "./modules/games/clock-expiration.js";`,
  "app clock import",
);

replaceOnce(
  "apps/api/src/app.ts",
`    app.addHook("onReady", async () => {
      stopClockExpirationService = startClockExpirationService({`,
`    app.addHook("onReady", async () => {
      const recovered = await recoverGameClocksOnStartup();
      if (recovered > 0) {
        app.log.info({ recovered }, "Recovered expired game clocks on startup");
      }

      stopClockExpirationService = startClockExpirationService({`,
  "app startup recovery",
);

// 5) Add lifecycle imports.
replaceOnce(
  "apps/api/src/modules/games/routes.ts",
`import {
  gameIdSchema,
  gameInputSchema,
  gameListQuerySchema,
  scoreActionSchema,
} from "./schemas.js";`,
`import {
  gameIdSchema,
  gameInputSchema,
  gameListQuerySchema,
  scoreActionSchema,
} from "./schemas.js";
import {
  GameLifecycleError,
  gameLifecycleCommandSchema,
  resolveLifecycleAction,
} from "./lifecycle.js";`,
  "lifecycle route imports",
);

// 6) Add lifecycle endpoint immediately before broadcast endpoint.
const routesPath = "apps/api/src/modules/games/routes.ts";
let routes = read(routesPath);
const routeMarker = `  app.post("/games/:id/broadcast", async (request, reply) => {`;
if (!routes.includes(routeMarker)) {
  throw new Error("lifecycle route insertion marker not found");
}

const lifecycleRoute = `  app.post("/games/:id/lifecycle", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = gameLifecycleCommandSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid lifecycle command",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findGameById(id.data);
    if (!existing) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: existing.organizationId,
    });

    let action;
    try {
      action = resolveLifecycleAction(existing, parsed.data.command);
    } catch (error) {
      if (error instanceof GameLifecycleError) {
        return reply.code(400).send({ error: error.message });
      }
      throw error;
    }

    let result;
    try {
      result = await applyGameScoringAction(
        id.data,
        action,
        parsed.data.commandId,
      );
    } catch (error) {
      if (error instanceof IdempotencyConflictError) {
        return reply.code(409).send({ error: error.message });
      }
      if (error instanceof GamePhaseError) {
        return reply.code(400).send({ error: error.message });
      }
      throw error;
    }

    if (!result) {
      if (parsed.data.commandId) {
        const game = await findGameById(id.data);
        if (!game) return reply.code(404).send({ error: "Game not found" });
        return {
          game,
          command: parsed.data.command,
          replayed: true,
        };
      }

      return reply.code(404).send({ error: "Game not found" });
    }

    const { game } = result;

    await audit(identity.sub, "game.lifecycle", {
      gameId: game.id,
      organizationId: game.organizationId,
      command: parsed.data.command,
      commandId: parsed.data.commandId,
      gamePhase: game.gamePhase,
      period: game.period,
      status: game.status,
      clockRemainingMs: game.clockRemainingMs,
    });

    return {
      game,
      command: parsed.data.command,
      replayed: false,
    };
  });

`;

routes = routes.replace(routeMarker, lifecycleRoute + routeMarker);
write(routesPath, routes);
NODE

echo
echo "============================================="
echo " SportsOS Next - Game Engine 2.2"
echo " Lifecycle + Recovery"
echo "============================================="
echo
echo "Applied successfully."
echo
echo "Created:"
echo "  $LIFECYCLE"
echo "  $LIFECYCLE_TEST"
echo "  $RECOVERY_TEST"
echo
echo "Modified:"
echo "  $ENGINE"
echo "  $ROUTES"
echo "  $CLOCK"
echo "  $APP"
echo "  $FLOW_TEST"
echo
echo "Backups:"
echo "  $BACKUP_DIR"
echo
echo "Run next:"
echo "  npm run typecheck"
echo "  npm test"
