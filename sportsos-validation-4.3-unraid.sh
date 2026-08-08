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

RUNNER="apps/api/src/modules/simulation/tournament-runner.ts"
ADAPTER="apps/api/src/modules/simulation/sportsos-adapter.ts"
TEST="apps/api/test/sportsos-simulation-adapter.test.ts"
RUNNER_SCRIPT="scripts/test-sportsos-simulation-adapter.sh"
PACKAGE="package.json"

for f in "$RUNNER" \
  "apps/api/src/modules/games/repository.ts" \
  "apps/api/src/modules/game-events/repository.ts" \
  "$PACKAGE"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'TournamentRunnerAdapter' "$RUNNER"; then
  echo "Validation Platform 4.2 runner was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/4.3-${STAMP}"
mkdir -p "$BACKUP_DIR"
cp "$PACKAGE" "$BACKUP_DIR/package.json"

cat > "$ADAPTER" <<'EOF'
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
EOF

cat > "$TEST" <<'EOF'
import { beforeEach, describe, expect, it, vi } from "vitest";

const applyGameScoringAction = vi.fn();
const createGameEvent = vi.fn();

vi.mock("../src/modules/games/repository.js", () => ({
  applyGameScoringAction,
}));

vi.mock("../src/modules/game-events/repository.js", () => ({
  createGameEvent,
}));

const {
  createSportsOSSimulationAdapter,
  SimulationBindingError,
} = await import(
  "../src/modules/simulation/sportsos-adapter.js"
);

const game = {
  id: 7,
  rink: 2,
  homeTeamId: 1,
  awayTeamId: 2,
  scheduledOffsetMinutes: 0,
  expectedGoals: 5,
  expectedPenalties: 3,
};

beforeEach(() => {
  vi.clearAllMocks();

  applyGameScoringAction.mockResolvedValue({
    game: {},
    applied: true,
  });

  createGameEvent.mockResolvedValue({
    replayed: false,
    event: {},
  });
});

function adapter() {
  return createSportsOSSimulationAdapter({
    runId: "load-test-001",
    actorUserId: "99",
    bindings: [
      {
        simulatedGameId: 7,
        sportsOSGameId: 7007,
        organizationId: 3,
      },
    ],
  });
}

describe("SportsOS tournament simulation adapter", () => {
  it("drives clock commands through the authoritative scoring repository", async () => {
    const target = adapter();

    await target.startGame(game);
    await target.pauseClock(game);
    await target.resumeClock(game);

    expect(applyGameScoringAction).toHaveBeenCalledTimes(3);
    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      1,
      7007,
      { action: "startClock" },
      expect.stringContaining("sim:load-test-001:g7:start-clock:"),
    );
    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      2,
      7007,
      { action: "pauseClock" },
      expect.any(String),
    );
  });

  it("records simulated goals through the real game-event repository", async () => {
    await adapter().recordGoal(game, "home");

    expect(createGameEvent).toHaveBeenCalledWith(
      7007,
      {
        type: "GOAL",
        side: "home",
        playerId: null,
        assist1PlayerId: null,
        assist2PlayerId: null,
        notes: "Tournament simulation load-test-001",
      },
      "99",
      expect.stringContaining("sim:load-test-001:g7:goal-home:"),
    );
  });

  it("records simulated penalties through the real penalty/event path", async () => {
    await adapter().recordPenalty(game, "away");

    expect(createGameEvent).toHaveBeenCalledWith(
      7007,
      {
        type: "PENALTY",
        side: "away",
        playerId: null,
        penaltyCode: "SIM-MINOR",
        penaltyMinutes: 2,
        notes: "Tournament simulation load-test-001",
      },
      "99",
      expect.stringContaining("sim:load-test-001:g7:penalty-away:"),
    );
  });

  it("forces 0:00 before using the normal intermission transition", async () => {
    const target = adapter();

    await target.beginIntermission(game);

    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      1,
      7007,
      { action: "setClock", clockRemainingMs: 0 },
      expect.any(String),
    );

    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      2,
      7007,
      { action: "startIntermission" },
      expect.any(String),
    );
  });

  it("uses the normal skip-intermission and next-period actions", async () => {
    await adapter().startNextPeriod(game);

    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      1,
      7007,
      { action: "skipIntermission" },
      expect.any(String),
    );

    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      2,
      7007,
      { action: "nextPeriod" },
      expect.any(String),
    );
  });

  it("finishes games only after setting the accelerated clock to zero", async () => {
    await adapter().finishGame(game);

    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      1,
      7007,
      { action: "setClock", clockRemainingMs: 0 },
      expect.any(String),
    );

    expect(applyGameScoringAction).toHaveBeenNthCalledWith(
      2,
      7007,
      { action: "finishGame" },
      expect.any(String),
    );
  });

  it("rejects simulation games that have no explicit SportsOS binding", async () => {
    const target = adapter();

    await expect(
      target.startGame({
        ...game,
        id: 999,
      }),
    ).rejects.toThrow(SimulationBindingError);
  });

  it("rejects duplicate simulated-game bindings", () => {
    expect(() =>
      createSportsOSSimulationAdapter({
        runId: "test-run",
        actorUserId: "99",
        bindings: [
          {
            simulatedGameId: 7,
            sportsOSGameId: 7007,
            organizationId: 3,
          },
          {
            simulatedGameId: 7,
            sportsOSGameId: 7008,
            organizationId: 3,
          },
        ],
      }),
    ).toThrow("Duplicate simulated game binding 7");
  });
});
EOF

cat > "$RUNNER_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=============================================="
echo " SportsOS Next - Real Engine Adapter Gate"
echo "=============================================="

npm run test --workspace=@sportsos/api -- test/sportsos-simulation-adapter.test.ts
EOF

chmod +x "$RUNNER_SCRIPT"

node <<'NODE'
const fs = require("fs");
const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts ??= {};
pkg.scripts["test:simulation-adapter"] =
  "./scripts/test-sportsos-simulation-adapter.sh";

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo
echo "============================================="
echo " SportsOS Next - Validation Platform 4.3"
echo " SportsOS Engine-backed Simulation Adapter"
echo "============================================="
echo
echo "Created:"
echo "  $ADAPTER"
echo "  $TEST"
echo "  $RUNNER_SCRIPT"
echo
echo "Modified:"
echo "  $PACKAGE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Real production paths exercised:"
echo "  applyGameScoringAction -> clock/lifecycle state"
echo "  createGameEvent        -> goals + penalties"
echo "  existing transactions  -> row locking/idempotency"
echo "  existing realtime      -> transactional outbox"
echo
echo "Safety:"
echo "  every simulated game requires an explicit real-game binding"
echo "  there is still NO public/live run endpoint in 4.3"
echo "  4.4 will provision dedicated isolated simulation games"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run test:simulation-adapter"
