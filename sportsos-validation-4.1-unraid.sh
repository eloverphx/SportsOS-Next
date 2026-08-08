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

APP="apps/api/src/app.ts"
ENGINE="apps/api/src/modules/simulation/tournament-simulator.ts"
ROUTES="apps/api/src/modules/simulation/routes.ts"
TEST="apps/api/test/tournament-simulator.test.ts"
RUNNER="scripts/test-tournament-simulation.sh"
PACKAGE="package.json"

for f in "$APP" "$PACKAGE"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/4.1-${STAMP}"
mkdir -p "$BACKUP_DIR/$(dirname "$APP")"
cp "$APP" "$BACKUP_DIR/$APP"
cp "$PACKAGE" "$BACKUP_DIR/package.json"

mkdir -p "$(dirname "$ENGINE")"
mkdir -p "$(dirname "$RUNNER")"

cat > "$ENGINE" <<'EOF'
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
EOF

cat > "$ROUTES" <<'EOF'
import type { FastifyInstance } from "fastify";
import { PERMISSIONS, requirePermission } from "../auth/index.js";
import {
  generateGameEventStream,
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  summarizeTournamentSimulation,
} from "./tournament-simulator.js";

export async function simulationRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.post("/simulation/tournaments/preview", async (request) => {
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    const config = normalizeTournamentSimulationConfig(
      (request.body ?? {}) as Record<string, unknown>,
    );

    const plan = generateTournamentPlan(config);

    return {
      config,
      plan,
      summary: summarizeTournamentSimulation(plan, config),
    };
  });

  app.post("/simulation/games/:id/events", async (request, reply) => {
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    const gameId = Number((request.params as { id: string }).id);
    if (!Number.isInteger(gameId) || gameId <= 0) {
      return reply.code(400).send({ error: "Invalid simulated game id" });
    }

    const config = normalizeTournamentSimulationConfig(
      (request.body ?? {}) as Record<string, unknown>,
    );
    const plan = generateTournamentPlan(config);
    const game = plan.games.find((candidate) => candidate.id === gameId);

    if (!game) {
      return reply.code(404).send({ error: "Simulated game not found" });
    }

    return {
      game,
      events: generateGameEventStream(game, config),
    };
  });
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  createSimulationRandom,
  generateGameEventStream,
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  summarizeTournamentSimulation,
} from "../src/modules/simulation/tournament-simulator.js";

describe("tournament simulator foundation", () => {
  it("produces deterministic random sequences from the same seed", () => {
    const first = createSimulationRandom(42);
    const second = createSimulationRandom(42);

    expect(
      Array.from({ length: 10 }, () => first()),
    ).toEqual(
      Array.from({ length: 10 }, () => second()),
    );
  });

  it("generates the same tournament plan from the same configuration", () => {
    const config = {
      seed: 12345,
      rinkCount: 8,
      teamCount: 48,
      gameCount: 120,
      playersPerTeam: 15,
    };

    expect(generateTournamentPlan(config)).toEqual(
      generateTournamentPlan(config),
    );
  });

  it("generates different tournament plans from different seeds", () => {
    const first = generateTournamentPlan({
      seed: 1,
      gameCount: 20,
    });

    const second = generateTournamentPlan({
      seed: 2,
      gameCount: 20,
    });

    expect(first.games).not.toEqual(second.games);
  });

  it("never schedules a team against itself", () => {
    const plan = generateTournamentPlan({
      seed: 99,
      teamCount: 48,
      gameCount: 1_000,
    });

    expect(
      plan.games.every(
        (game) => game.homeTeamId !== game.awayTeamId,
      ),
    ).toBe(true);
  });

  it("keeps every generated game assigned to an available rink", () => {
    const plan = generateTournamentPlan({
      rinkCount: 8,
      gameCount: 500,
    });

    expect(
      plan.games.every(
        (game) => game.rink >= 1 && game.rink <= 8,
      ),
    ).toBe(true);
  });

  it("generates the configured number of goals and penalties per game", () => {
    const config = normalizeTournamentSimulationConfig({
      seed: 71,
      regulationPeriods: 3,
    });

    const game = generateTournamentPlan({
      ...config,
      gameCount: 1,
    }).games[0]!;

    const events = generateGameEventStream(game, config);

    expect(
      events.filter((event) => event.type === "GOAL"),
    ).toHaveLength(game.expectedGoals);

    expect(
      events.filter((event) => event.type === "PENALTY"),
    ).toHaveLength(game.expectedPenalties);

    expect(events.at(-1)?.type).toBe("FINAL");
  });

  it("supports a realistic 32-game simultaneous tournament scenario", () => {
    const config = {
      name: "SportsOS Load Tournament",
      seed: 20260808,
      rinkCount: 32,
      teamCount: 64,
      gameCount: 128,
      playersPerTeam: 16,
    };

    const plan = generateTournamentPlan(config);
    const summary = summarizeTournamentSimulation(plan, config);

    expect(summary.games).toBe(128);
    expect(summary.rinks).toBe(32);
    expect(summary.teams).toBe(64);
    expect(summary.players).toBe(1_024);
    expect(summary.events).toBeGreaterThan(summary.games);
    expect(summary.goals).toBe(plan.totals.expectedGoals);
    expect(summary.penalties).toBe(plan.totals.expectedPenalties);
  });

  it("clamps unsafe configuration sizes", () => {
    const config = normalizeTournamentSimulationConfig({
      rinkCount: 999,
      teamCount: 9_999,
      gameCount: 999_999,
      playersPerTeam: 200,
    });

    expect(config.rinkCount).toBe(64);
    expect(config.teamCount).toBe(256);
    expect(config.gameCount).toBe(2_000);
    expect(config.playersPerTeam).toBe(30);
  });
});
EOF

cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " SportsOS Next - Tournament Simulation"
echo "========================================"

npm run test --workspace=@sportsos/api -- test/tournament-simulator.test.ts
EOF

chmod +x "$RUNNER"

node <<'NODE'
const fs = require("fs");

const appPath = "apps/api/src/app.ts";
let app = fs.readFileSync(appPath, "utf8");

if (!app.includes("simulationRoutes")) {
  const importAnchor =
    'import { gameEngineTelemetryRoutes } from "./modules/games/telemetry-routes.js";';

  if (!app.includes(importAnchor)) {
    throw new Error("Could not locate gameEngineTelemetryRoutes import");
  }

  app = app.replace(
    importAnchor,
`${importAnchor}
import { simulationRoutes } from "./modules/simulation/routes.js";`,
  );
}

if (!app.includes("app.register(simulationRoutes)")) {
  const registerAnchor = "await app.register(gameEngineTelemetryRoutes);";

  if (!app.includes(registerAnchor)) {
    throw new Error("Could not locate gameEngineTelemetryRoutes registration");
  }

  app = app.replace(
    registerAnchor,
`${registerAnchor}
  await app.register(simulationRoutes);`,
  );
}

fs.writeFileSync(appPath, app);

const packagePath = "package.json";
const pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"));
pkg.scripts ??= {};
pkg.scripts["test:tournament-simulation"] =
  "./scripts/test-tournament-simulation.sh";
fs.writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo
echo "============================================="
echo " SportsOS Next - Validation Platform 4.1"
echo " Deterministic Tournament Simulator"
echo "============================================="
echo
echo "Created:"
echo "  $ENGINE"
echo "  $ROUTES"
echo "  $TEST"
echo "  $RUNNER"
echo
echo "Modified:"
echo "  $APP"
echo "  $PACKAGE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "New API:"
echo "  POST /simulation/tournaments/preview"
echo "  POST /simulation/games/:id/events"
echo
echo "New command:"
echo "  npm run test:tournament-simulation"
echo
echo "Important:"
echo "  4.1 is deterministic and read-only."
echo "  It does NOT create or alter tournament/game data in MySQL."
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run test:tournament-simulation"
