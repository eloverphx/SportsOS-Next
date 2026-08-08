export interface TournamentSimulationConfig {
  name: string;
  seed: number;
  rinkCount: number;
  teamCount: number;
  gameCount: number;
  playersPerTeam: number;
  regulationPeriods: number;
  periodLengthMs: number;
  intermissionLengthMs: number;
}

export interface SimulatedTeam {
  id: number;
  name: string;
  playerCount: number;
}

export interface SimulatedGame {
  id: number;
  rink: number;
  homeTeamId: number;
  awayTeamId: number;
  scheduledOffsetMinutes: number;
  expectedGoals: number;
  expectedPenalties: number;
}

export interface SimulatedTournamentPlan {
  name: string;
  seed: number;
  rinkCount: number;
  teams: SimulatedTeam[];
  games: SimulatedGame[];
  totals: {
    players: number;
    expectedGoals: number;
    expectedPenalties: number;
  };
}

export type SimulatedGameEventType =
  | "CLOCK_START"
  | "CLOCK_PAUSE"
  | "GOAL"
  | "PENALTY"
  | "INTERMISSION"
  | "PERIOD_START"
  | "FINAL";

export interface SimulatedGameEvent {
  sequence: number;
  gameId: number;
  elapsedSimulationMs: number;
  type: SimulatedGameEventType;
  side?: "home" | "away";
  detail?: string;
}

function clampInt(
  value: number,
  minimum: number,
  maximum: number,
): number {
  return Math.max(minimum, Math.min(maximum, Math.floor(value)));
}

function normalizeSeed(seed: number): number {
  const normalized = Math.floor(seed) >>> 0;
  return normalized === 0 ? 0x6d2b79f5 : normalized;
}

/**
 * Mulberry32 PRNG. Deterministic, tiny, and sufficient for simulation/testing.
 * This is not used for security-sensitive randomness.
 */
export function createSimulationRandom(seed: number): () => number {
  let state = normalizeSeed(seed);

  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function randomInt(
  random: () => number,
  minimum: number,
  maximumInclusive: number,
): number {
  return (
    minimum +
    Math.floor(random() * (maximumInclusive - minimum + 1))
  );
}

function makeTeamName(index: number): string {
  const adjectives = [
    "North",
    "South",
    "Lake",
    "River",
    "Iron",
    "Ice",
    "Storm",
    "Prairie",
    "Metro",
    "Valley",
    "Twin",
    "Wild",
  ] as const;

  const mascots = [
    "Lakers",
    "Bears",
    "Hawks",
    "Wolves",
    "Blades",
    "Saints",
    "Falcons",
    "Tigers",
    "Eagles",
    "Knights",
    "Rockets",
    "Raiders",
  ] as const;

  return `${adjectives[index % adjectives.length]} ${
    mascots[Math.floor(index / adjectives.length) % mascots.length]
  } ${index + 1}`;
}

export function normalizeTournamentSimulationConfig(
  input: Partial<TournamentSimulationConfig>,
): TournamentSimulationConfig {
  return {
    name: input.name?.trim() || "SportsOS Simulation Tournament",
    seed: Number.isFinite(input.seed) ? Math.floor(input.seed!) : 20260808,
    rinkCount: clampInt(input.rinkCount ?? 8, 1, 64),
    teamCount: clampInt(input.teamCount ?? 48, 2, 256),
    gameCount: clampInt(input.gameCount ?? 120, 1, 2_000),
    playersPerTeam: clampInt(input.playersPerTeam ?? 15, 5, 30),
    regulationPeriods: clampInt(input.regulationPeriods ?? 3, 1, 6),
    periodLengthMs: clampInt(input.periodLengthMs ?? 900_000, 60_000, 3_600_000),
    intermissionLengthMs: clampInt(
      input.intermissionLengthMs ?? 600_000,
      0,
      3_600_000,
    ),
  };
}

export function generateTournamentPlan(
  input: Partial<TournamentSimulationConfig> = {},
): SimulatedTournamentPlan {
  const config = normalizeTournamentSimulationConfig(input);
  const random = createSimulationRandom(config.seed);

  const teams: SimulatedTeam[] = Array.from(
    { length: config.teamCount },
    (_, index) => ({
      id: index + 1,
      name: makeTeamName(index),
      playerCount: config.playersPerTeam,
    }),
  );

  const games: SimulatedGame[] = [];
  let round = 0;

  for (let index = 0; index < config.gameCount; index += 1) {
    const homeIndex = index % config.teamCount;
    let awayIndex =
      (index + 1 + round * 3) % config.teamCount;

    if (awayIndex === homeIndex) {
      awayIndex = (awayIndex + 1) % config.teamCount;
    }

    const expectedGoals = randomInt(random, 2, 10);
    const expectedPenalties = randomInt(random, 0, 12);

    games.push({
      id: index + 1,
      rink: (index % config.rinkCount) + 1,
      homeTeamId: teams[homeIndex]!.id,
      awayTeamId: teams[awayIndex]!.id,
      scheduledOffsetMinutes:
        Math.floor(index / config.rinkCount) * 90,
      expectedGoals,
      expectedPenalties,
    });

    if ((index + 1) % config.rinkCount === 0) {
      round += 1;
    }
  }

  return {
    name: config.name,
    seed: config.seed,
    rinkCount: config.rinkCount,
    teams,
    games,
    totals: {
      players: teams.reduce((sum, team) => sum + team.playerCount, 0),
      expectedGoals: games.reduce(
        (sum, game) => sum + game.expectedGoals,
        0,
      ),
      expectedPenalties: games.reduce(
        (sum, game) => sum + game.expectedPenalties,
        0,
      ),
    },
  };
}

export function generateGameEventStream(
  game: SimulatedGame,
  configInput: Partial<TournamentSimulationConfig> = {},
): SimulatedGameEvent[] {
  const config = normalizeTournamentSimulationConfig(configInput);
  const random = createSimulationRandom(config.seed ^ game.id);
  const events: SimulatedGameEvent[] = [];
  let sequence = 1;
  let elapsed = 0;

  const push = (
    type: SimulatedGameEventType,
    side?: "home" | "away",
    detail?: string,
  ): void => {
    events.push({
      sequence,
      gameId: game.id,
      elapsedSimulationMs: elapsed,
      type,
      side,
      detail,
    });
    sequence += 1;
  };

  for (let period = 1; period <= config.regulationPeriods; period += 1) {
    push(period === 1 ? "CLOCK_START" : "PERIOD_START", undefined, `Period ${period}`);

    const periodEvents: Array<{
      at: number;
      type: "GOAL" | "PENALTY";
      side: "home" | "away";
    }> = [];

    const periodGoalCount =
      Math.floor(game.expectedGoals / config.regulationPeriods) +
      (period <= game.expectedGoals % config.regulationPeriods ? 1 : 0);

    const periodPenaltyCount =
      Math.floor(game.expectedPenalties / config.regulationPeriods) +
      (period <= game.expectedPenalties % config.regulationPeriods ? 1 : 0);

    for (let index = 0; index < periodGoalCount; index += 1) {
      periodEvents.push({
        at: randomInt(random, 1_000, Math.max(1_000, config.periodLengthMs - 1_000)),
        type: "GOAL",
        side: random() >= 0.5 ? "home" : "away",
      });
    }

    for (let index = 0; index < periodPenaltyCount; index += 1) {
      periodEvents.push({
        at: randomInt(random, 1_000, Math.max(1_000, config.periodLengthMs - 1_000)),
        type: "PENALTY",
        side: random() >= 0.5 ? "home" : "away",
      });
    }

    periodEvents.sort((left, right) => left.at - right.at);

    for (const event of periodEvents) {
      elapsed += event.at;
      push(event.type, event.side);
      elapsed += randomInt(random, 1_000, 15_000);
      push("CLOCK_PAUSE");
      elapsed += randomInt(random, 500, 5_000);
      push("CLOCK_START");
    }

    elapsed += config.periodLengthMs;
    push("CLOCK_PAUSE", undefined, `End period ${period}`);

    if (period < config.regulationPeriods) {
      push("INTERMISSION", undefined, `Intermission ${period}`);
      elapsed += config.intermissionLengthMs;
    }
  }

  push("FINAL");

  return events;
}

export function summarizeTournamentSimulation(
  plan: SimulatedTournamentPlan,
  configInput: Partial<TournamentSimulationConfig> = {},
): {
  games: number;
  events: number;
  goals: number;
  penalties: number;
  rinks: number;
  teams: number;
  players: number;
} {
  let events = 0;
  let goals = 0;
  let penalties = 0;

  for (const game of plan.games) {
    const stream = generateGameEventStream(game, {
      ...configInput,
      seed: plan.seed,
    });

    events += stream.length;
    goals += stream.filter((event) => event.type === "GOAL").length;
    penalties += stream.filter((event) => event.type === "PENALTY").length;
  }

  return {
    games: plan.games.length,
    events,
    goals,
    penalties,
    rinks: plan.rinkCount,
    teams: plan.teams.length,
    players: plan.totals.players,
  };
}
