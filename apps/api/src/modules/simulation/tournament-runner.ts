import {
  generateGameEventStream,
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  type SimulatedGame,
  type SimulatedGameEvent,
  type TournamentSimulationConfig,
} from "./tournament-simulator.js";

export interface TournamentRunnerAdapter {
  startGame(game: SimulatedGame): Promise<void>;
  pauseClock(game: SimulatedGame): Promise<void>;
  resumeClock(game: SimulatedGame): Promise<void>;
  recordGoal(
    game: SimulatedGame,
    side: "home" | "away",
  ): Promise<void>;
  recordPenalty(
    game: SimulatedGame,
    side: "home" | "away",
  ): Promise<void>;
  beginIntermission(game: SimulatedGame): Promise<void>;
  startNextPeriod(game: SimulatedGame): Promise<void>;
  finishGame(game: SimulatedGame): Promise<void>;
}

export interface TournamentRunOptions {
  concurrency?: number;
  failFast?: boolean;
}

export interface TournamentGameRunResult {
  gameId: number;
  success: boolean;
  processedEvents: number;
  error?: string;
}

export interface TournamentRunResult {
  startedAt: string;
  finishedAt: string;
  durationMs: number;
  games: number;
  succeeded: number;
  failed: number;
  processedEvents: number;
  results: TournamentGameRunResult[];
}

async function applySimulatedEvent(
  adapter: TournamentRunnerAdapter,
  game: SimulatedGame,
  event: SimulatedGameEvent,
): Promise<void> {
  switch (event.type) {
    case "CLOCK_START":
      await adapter.startGame(game);
      break;
    case "CLOCK_PAUSE":
      await adapter.pauseClock(game);
      break;
    case "PERIOD_START":
      await adapter.startNextPeriod(game);
      break;
    case "GOAL":
      if (!event.side) {
        throw new Error("Simulated goal is missing a team side");
      }
      await adapter.recordGoal(game, event.side);
      break;
    case "PENALTY":
      if (!event.side) {
        throw new Error("Simulated penalty is missing a team side");
      }
      await adapter.recordPenalty(game, event.side);
      break;
    case "INTERMISSION":
      await adapter.beginIntermission(game);
      break;
    case "FINAL":
      await adapter.finishGame(game);
      break;
  }
}

async function runOneGame(
  adapter: TournamentRunnerAdapter,
  game: SimulatedGame,
  config: TournamentSimulationConfig,
): Promise<TournamentGameRunResult> {
  const events = generateGameEventStream(game, config);
  let processedEvents = 0;

  try {
    for (const event of events) {
      await applySimulatedEvent(adapter, game, event);
      processedEvents += 1;
    }

    return {
      gameId: game.id,
      success: true,
      processedEvents,
    };
  } catch (error) {
    return {
      gameId: game.id,
      success: false,
      processedEvents,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

export async function runTournamentSimulation(
  adapter: TournamentRunnerAdapter,
  input: Partial<TournamentSimulationConfig> = {},
  options: TournamentRunOptions = {},
): Promise<TournamentRunResult> {
  const config = normalizeTournamentSimulationConfig(input);
  const plan = generateTournamentPlan(config);

  const concurrency = Math.max(
    1,
    Math.min(128, Math.floor(options.concurrency ?? config.rinkCount)),
  );

  const started = Date.now();
  const results: TournamentGameRunResult[] = [];
  let nextIndex = 0;
  let stopped = false;

  const worker = async (): Promise<void> => {
    while (!stopped) {
      const index = nextIndex;
      nextIndex += 1;

      if (index >= plan.games.length) return;

      const game = plan.games[index]!;
      const result = await runOneGame(adapter, game, config);
      results.push(result);

      if (!result.success && options.failFast) {
        stopped = true;
        return;
      }
    }
  };

  await Promise.all(
    Array.from(
      { length: Math.min(concurrency, plan.games.length) },
      () => worker(),
    ),
  );

  results.sort((left, right) => left.gameId - right.gameId);

  const finished = Date.now();
  const succeeded = results.filter((result) => result.success).length;
  const failed = results.length - succeeded;

  return {
    startedAt: new Date(started).toISOString(),
    finishedAt: new Date(finished).toISOString(),
    durationMs: finished - started,
    games: results.length,
    succeeded,
    failed,
    processedEvents: results.reduce(
      (sum, result) => sum + result.processedEvents,
      0,
    ),
    results,
  };
}
