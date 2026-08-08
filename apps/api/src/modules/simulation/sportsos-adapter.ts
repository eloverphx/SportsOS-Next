import { createGameEvent } from "../game-events/repository.js";
import { applyGameScoringAction } from "../games/repository.js";
import type {
  SimulatedGame,
} from "./tournament-simulator.js";
import type {
  TournamentRunnerAdapter,
} from "./tournament-runner.js";

export interface SportsOSSimulationGameBinding {
  simulatedGameId: number;
  sportsOSGameId: number;
  organizationId: number;
}

export interface SportsOSSimulationAdapterOptions {
  bindings: SportsOSSimulationGameBinding[];
  actorUserId: string;
  runId: string;
}

export class SimulationBindingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SimulationBindingError";
  }
}

function safeRunId(value: string): string {
  const normalized = value
    .trim()
    .replace(/[^A-Za-z0-9._:-]/g, "-")
    .slice(0, 40);

  if (normalized.length < 4) {
    throw new SimulationBindingError(
      "Simulation runId must contain at least four safe characters",
    );
  }

  return normalized;
}

export function createSportsOSSimulationAdapter(
  options: SportsOSSimulationAdapterOptions,
): TournamentRunnerAdapter {
  const runId = safeRunId(options.runId);

  if (!options.actorUserId.trim()) {
    throw new SimulationBindingError(
      "Simulation actorUserId is required",
    );
  }

  const bindingMap = new Map<number, SportsOSSimulationGameBinding>();

  for (const binding of options.bindings) {
    if (
      !Number.isInteger(binding.simulatedGameId) ||
      binding.simulatedGameId <= 0 ||
      !Number.isInteger(binding.sportsOSGameId) ||
      binding.sportsOSGameId <= 0 ||
      !Number.isInteger(binding.organizationId) ||
      binding.organizationId <= 0
    ) {
      throw new SimulationBindingError(
        "Simulation game bindings must use positive integer ids",
      );
    }

    if (bindingMap.has(binding.simulatedGameId)) {
      throw new SimulationBindingError(
        `Duplicate simulated game binding ${binding.simulatedGameId}`,
      );
    }

    bindingMap.set(binding.simulatedGameId, binding);
  }

  let commandSequence = 0;

  const bindingFor = (
    game: SimulatedGame,
  ): SportsOSSimulationGameBinding => {
    const binding = bindingMap.get(game.id);

    if (!binding) {
      throw new SimulationBindingError(
        `No SportsOS game binding exists for simulated game ${game.id}`,
      );
    }

    return binding;
  };

  const commandId = (
    game: SimulatedGame,
    action: string,
  ): string => {
    commandSequence += 1;
    return `sim:${runId}:g${game.id}:${action}:${commandSequence}`;
  };

  const scoringAction = async (
    game: SimulatedGame,
    action:
      | { action: "startClock" }
      | { action: "pauseClock" }
      | { action: "setClock"; clockRemainingMs: number }
      | { action: "startIntermission" }
      | { action: "nextPeriod" }
      | { action: "finishGame" },
    actionName: string,
  ): Promise<void> => {
    const binding = bindingFor(game);

    const result = await applyGameScoringAction(
      binding.sportsOSGameId,
      action,
      commandId(game, actionName),
    );

    // A null result is an idempotent replay in the existing scoring repository.
    // That is safe during simulation and should not be treated as a failure.
    if (result === undefined) {
      throw new Error(
        `SportsOS game ${binding.sportsOSGameId} was not found`,
      );
    }
  };

  return {
    async startGame(game) {
      await scoringAction(
        game,
        { action: "startClock" },
        "start-clock",
      );
    },

    async pauseClock(game) {
      await scoringAction(
        game,
        { action: "pauseClock" },
        "pause-clock",
      );
    },

    async resumeClock(game) {
      await scoringAction(
        game,
        { action: "startClock" },
        "resume-clock",
      );
    },

    async recordGoal(game, side) {
      const binding = bindingFor(game);

      await createGameEvent(
        binding.sportsOSGameId,
        {
          type: "GOAL",
          side,
          playerId: null,
          assist1PlayerId: null,
          assist2PlayerId: null,
          notes: `Tournament simulation ${runId}`,
        },
        options.actorUserId,
        commandId(game, `goal-${side}`),
      );
    },

    async recordPenalty(game, side) {
      const binding = bindingFor(game);

      await createGameEvent(
        binding.sportsOSGameId,
        {
          type: "PENALTY",
          side,
          playerId: null,
          penaltyCode: "SIM-MINOR",
          penaltyMinutes: 2,
          notes: `Tournament simulation ${runId}`,
        },
        options.actorUserId,
        commandId(game, `penalty-${side}`),
      );
    },

    async beginIntermission(game) {
      // Accelerated simulations do not wait real period duration. Materialize
      // 0:00 first so the normal SportsOS phase validation remains authoritative.
      await scoringAction(
        game,
        { action: "setClock", clockRemainingMs: 0 },
        "period-clock-zero",
      );

      await scoringAction(
        game,
        { action: "startIntermission" },
        "start-intermission",
      );
    },

    async startNextPeriod(game) {
      // Accelerated execution also skips real intermission duration. The game
      // engine remains responsible for validating the actual phase transition.
      const binding = bindingFor(game);

      await applyGameScoringAction(
        binding.sportsOSGameId,
        { action: "skipIntermission" },
        commandId(game, "skip-intermission"),
      );

      await applyGameScoringAction(
        binding.sportsOSGameId,
        { action: "nextPeriod" },
        commandId(game, "next-period"),
      );
    },

    async finishGame(game) {
      // Ensure the final simulated regulation period has reached 0:00 before
      // committing the authoritative FINAL transition.
      await scoringAction(
        game,
        { action: "setClock", clockRemainingMs: 0 },
        "final-clock-zero",
      );

      await scoringAction(
        game,
        { action: "finishGame" },
        "finish-game",
      );
    },
  };
}
