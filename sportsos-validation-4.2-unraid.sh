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

SIM="apps/api/src/modules/simulation/tournament-simulator.ts"
RUNNER_MOD="apps/api/src/modules/simulation/tournament-runner.ts"
TEST="apps/api/test/tournament-runner.test.ts"
RUNNER_SCRIPT="scripts/test-tournament-runner.sh"
PACKAGE="package.json"

for f in "$SIM" "$PACKAGE"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/4.2-${STAMP}"
mkdir -p "$BACKUP_DIR"
cp "$PACKAGE" "$BACKUP_DIR/package.json"

cat > "$RUNNER_MOD" <<'EOF'
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
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it, vi } from "vitest";
import {
  runTournamentSimulation,
  type TournamentRunnerAdapter,
} from "../src/modules/simulation/tournament-runner.js";

function adapter(): TournamentRunnerAdapter {
  return {
    startGame: vi.fn(async () => undefined),
    pauseClock: vi.fn(async () => undefined),
    resumeClock: vi.fn(async () => undefined),
    recordGoal: vi.fn(async () => undefined),
    recordPenalty: vi.fn(async () => undefined),
    beginIntermission: vi.fn(async () => undefined),
    startNextPeriod: vi.fn(async () => undefined),
    finishGame: vi.fn(async () => undefined),
  };
}

describe("accelerated tournament runner", () => {
  it("runs a deterministic multi-game tournament through the adapter", async () => {
    const target = adapter();

    const result = await runTournamentSimulation(
      target,
      {
        seed: 20260808,
        rinkCount: 8,
        teamCount: 32,
        gameCount: 40,
      },
      {
        concurrency: 8,
      },
    );

    expect(result.games).toBe(40);
    expect(result.succeeded).toBe(40);
    expect(result.failed).toBe(0);
    expect(result.processedEvents).toBeGreaterThan(40);
    expect(target.finishGame).toHaveBeenCalledTimes(40);
  });

  it("supports 32 simultaneous workers across 128 games", async () => {
    const target = adapter();

    const result = await runTournamentSimulation(
      target,
      {
        seed: 77,
        rinkCount: 32,
        teamCount: 64,
        gameCount: 128,
      },
      {
        concurrency: 32,
      },
    );

    expect(result.games).toBe(128);
    expect(result.failed).toBe(0);
    expect(result.succeeded).toBe(128);
  });

  it("isolates a failed game while allowing the tournament to continue", async () => {
    const target = adapter();
    const originalFinish = target.finishGame;

    target.finishGame = vi.fn(async (game) => {
      if (game.id === 7) {
        throw new Error("simulated adapter failure");
      }
      await originalFinish(game);
    });

    const result = await runTournamentSimulation(
      target,
      {
        seed: 1,
        rinkCount: 4,
        teamCount: 16,
        gameCount: 20,
      },
      {
        concurrency: 4,
        failFast: false,
      },
    );

    expect(result.games).toBe(20);
    expect(result.failed).toBe(1);
    expect(result.succeeded).toBe(19);
    expect(result.results.find((item) => item.gameId === 7)).toEqual(
      expect.objectContaining({
        success: false,
        error: "simulated adapter failure",
      }),
    );
  });

  it("stops scheduling new work when failFast is enabled", async () => {
    const target = adapter();

    target.startGame = vi.fn(async (game) => {
      if (game.id === 1) {
        throw new Error("stop now");
      }
    });

    const result = await runTournamentSimulation(
      target,
      {
        seed: 1,
        rinkCount: 1,
        teamCount: 12,
        gameCount: 20,
      },
      {
        concurrency: 1,
        failFast: true,
      },
    );

    expect(result.games).toBe(1);
    expect(result.failed).toBe(1);
  });

  it("produces stable event counts for the same seeded tournament", async () => {
    const first = await runTournamentSimulation(
      adapter(),
      {
        seed: 999,
        rinkCount: 6,
        teamCount: 24,
        gameCount: 36,
      },
    );

    const second = await runTournamentSimulation(
      adapter(),
      {
        seed: 999,
        rinkCount: 6,
        teamCount: 24,
        gameCount: 36,
      },
    );

    expect(first.games).toBe(second.games);
    expect(first.processedEvents).toBe(second.processedEvents);
    expect(
      first.results.map((item) => item.processedEvents),
    ).toEqual(
      second.results.map((item) => item.processedEvents),
    );
  });
});
EOF

cat > "$RUNNER_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " SportsOS Next - Tournament Runner Gate"
echo "========================================"

npm run test --workspace=@sportsos/api -- test/tournament-runner.test.ts
EOF

chmod +x "$RUNNER_SCRIPT"

node <<'NODE'
const fs = require("fs");
const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts ??= {};
pkg.scripts["test:tournament-runner"] =
  "./scripts/test-tournament-runner.sh";

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo
echo "============================================="
echo " SportsOS Next - Validation Platform 4.2"
echo " Accelerated Tournament Runner"
echo "============================================="
echo
echo "Created:"
echo "  $RUNNER_MOD"
echo "  $TEST"
echo "  $RUNNER_SCRIPT"
echo
echo "Modified:"
echo "  $PACKAGE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Capabilities:"
echo "  deterministic tournament execution"
echo "  configurable concurrency up to 128 workers"
echo "  per-game isolation"
echo "  fail-fast or continue-on-error"
echo "  processed event counts"
echo "  repeatability checks"
echo
echo "Important:"
echo "  4.2 still uses an adapter and does not mutate your live DB."
echo "  4.3 will provide the SportsOS engine-backed adapter."
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run test:tournament-runner"
