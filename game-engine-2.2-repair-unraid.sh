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
ROUTES="apps/api/src/modules/games/routes.ts"
CLOCK="apps/api/src/modules/games/clock-expiration.ts"
APP="apps/api/src/app.ts"
FLOW_TEST="apps/api/test/game-flow-regression.test.ts"
LIFECYCLE="apps/api/src/modules/games/lifecycle.ts"
LIFECYCLE_TEST="apps/api/test/game-lifecycle.test.ts"
RECOVERY_TEST="apps/api/test/game-recovery.test.ts"

for f in "$ENGINE" "$ROUTES" "$CLOCK" "$APP" "$FLOW_TEST"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/2.2-repair-${STAMP}"
mkdir -p "$BACKUP_DIR"

for f in "$ENGINE" "$ROUTES" "$CLOCK" "$APP" "$FLOW_TEST"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

# Re-create these deterministically in case the previous installer stopped midway.
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
  "status" | "gamePhase" | "period" | "regulationPeriods" | "clockRemainingMs"
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
        game({
          status: "SCHEDULED",
          gamePhase: "PREGAME",
          clockRemainingMs: 900_000,
        }),
        "startGame",
      ),
    ).toEqual({ action: "startClock" });
  });

  it("ends an early regulation period by beginning intermission", () => {
    expect(resolveLifecycleAction(game({ period: 1 }), "endPeriod")).toEqual({
      action: "startIntermission",
    });
  });

  it("leaves final regulation at zero for explicit overtime or final", () => {
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

  it("maps next-period, overtime, and finish commands", () => {
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

function candidate(id: number, overrides: Record<string, unknown> = {}) {
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
    const rows = [candidate(11), candidate(12)];

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

  it("recovers expired intermission without touching penalties", async () => {
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

  it("leaves still-running clocks timestamp-based", async () => {
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

function ensureReplace(path, oldText, newText, alreadyText, label) {
  let text = read(path);

  if (alreadyText && text.includes(alreadyText)) {
    console.log(`already applied: ${label}`);
    return;
  }

  if (!text.includes(oldText)) {
    throw new Error(`${label}: neither original nor already-applied form was found in ${path}`);
  }

  text = text.replace(oldText, newText);
  write(path, text);
  console.log(`applied: ${label}`);
}

// Engine changes may already have been applied by the first 2.2 run.
ensureReplace(
  "apps/api/src/modules/games/engine.ts",
`      state.period += 1;
      state.periodLengthMs = current.periodLengthMs;
      state.clockRemainingMs = state.periodLengthMs;`,
`      state.period += 1;
      state.periodLengthMs = state.regulationPeriodLengthMs;
      state.clockRemainingMs = state.regulationPeriodLengthMs;`,
`      state.periodLengthMs = state.regulationPeriodLengthMs;`,
  "future regulation periods use configured regulation length",
);

ensureReplace(
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
`// A scorer correction changes only the current clock.`,
  "manual setClock no longer changes configured period duration",
);

// Regression fixture may already be explicit.
ensureReplace(
  "apps/api/test/game-flow-regression.test.ts",
`        period: 1,
        period_length_ms: 720_000,
        intermission_remaining_ms: 0,`,
`        period: 1,
        period_length_ms: 720_000,
        regulation_period_length_ms: 720_000,
        intermission_remaining_ms: 0,`,
`        regulation_period_length_ms: 720_000,`,
  "regulation reset regression fixture",
);

// Recovery function.
{
  const path = "apps/api/src/modules/games/clock-expiration.ts";
  let text = read(path);

  if (!text.includes("export async function recoverGameClocksOnStartup(")) {
    const marker = "export function startClockExpirationService(";
    if (!text.includes(marker)) {
      throw new Error("startup recovery function insertion marker not found");
    }

    const addition = `/**
 * Reconcile persisted timers before the API becomes ready.
 *
 * Expired clocks are materialized transactionally. Timers that still have
 * remaining time retain their persisted started_at timestamp so reads can
 * reconstruct authoritative remaining time after restart.
 */
export async function recoverGameClocksOnStartup(
  nowMs = Date.now(),
): Promise<number> {
  return processExpiredGameClocks(nowMs);
}

`;

    text = text.replace(marker, addition + marker);
    write(path, text);
    console.log("applied: startup recovery function");
  } else {
    console.log("already applied: startup recovery function");
  }
}

// app.ts import - supports original or partially applied state.
{
  const path = "apps/api/src/app.ts";
  let text = read(path);

  if (!text.includes("recoverGameClocksOnStartup")) {
    const oldImport =
      'import { startClockExpirationService } from "./modules/games/clock-expiration.js";';

    if (!text.includes(oldImport)) {
      throw new Error("clock expiration import could not be located in app.ts");
    }

    text = text.replace(
      oldImport,
`import {
  recoverGameClocksOnStartup,
  startClockExpirationService,
} from "./modules/games/clock-expiration.js";`,
    );
    write(path, text);
    console.log("applied: app recovery import");
  } else {
    console.log("already applied: app recovery import");
  }
}

// app.ts onReady hook. Do not depend on exact indentation around the worker.
{
  const path = "apps/api/src/app.ts";
  let text = read(path);

  if (text.includes('Recovered expired game clocks on startup')) {
    console.log("already applied: blocking startup recovery");
  } else {
    const hook = 'app.addHook("onReady", async () => {';
    const hookIndex = text.indexOf(hook);
    if (hookIndex < 0) {
      throw new Error("Fastify onReady hook not found in app.ts");
    }

    const insertAt = hookIndex + hook.length;
    const recovery = `
      const recovered = await recoverGameClocksOnStartup();
      if (recovered > 0) {
        app.log.info({ recovered }, "Recovered expired game clocks on startup");
      }
`;

    text = text.slice(0, insertAt) + recovery + text.slice(insertAt);
    write(path, text);
    console.log("applied: blocking startup recovery");
  }
}

// lifecycle route imports.
{
  const path = "apps/api/src/modules/games/routes.ts";
  let text = read(path);

  if (!text.includes("gameLifecycleCommandSchema")) {
    const marker =
`import {
  gameIdSchema,
  gameInputSchema,
  gameListQuerySchema,
  scoreActionSchema,
} from "./schemas.js";`;

    if (!text.includes(marker)) {
      throw new Error("game schema import marker not found in routes.ts");
    }

    const addition =
`${marker}
import {
  GameLifecycleError,
  gameLifecycleCommandSchema,
  resolveLifecycleAction,
} from "./lifecycle.js";`;

    text = text.replace(marker, addition);
    write(path, text);
    console.log("applied: lifecycle route imports");
  } else {
    console.log("already applied: lifecycle route imports");
  }
}

// lifecycle route endpoint.
{
  const path = "apps/api/src/modules/games/routes.ts";
  let text = read(path);

  if (text.includes('app.post("/games/:id/lifecycle"')) {
    console.log("already applied: lifecycle endpoint");
  } else {
    const marker = '  app.post("/games/:id/broadcast", async (request, reply) => {';
    if (!text.includes(marker)) {
      throw new Error("broadcast route marker not found in routes.ts");
    }

    const route = `  app.post("/games/:id/lifecycle", async (request, reply) => {
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

    text = text.replace(marker, route + marker);
    write(path, text);
    console.log("applied: lifecycle endpoint");
  }
}
NODE

echo
echo "============================================="
echo " SportsOS Next - Game Engine 2.2 Repair"
echo "============================================="
echo
echo "Repair/continuation completed."
echo "Backup directory:"
echo "  $BACKUP_DIR"
echo
echo "Now run:"
echo "  npm run typecheck"
echo "  npm test"
