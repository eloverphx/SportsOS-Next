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

MIGRATIONS="apps/api/src/infrastructure/migrations.ts"
ROUTES="apps/api/src/modules/simulation/routes.ts"
PROVISIONER="apps/api/src/modules/simulation/provisioner.ts"
SIM="apps/api/src/modules/simulation/tournament-simulator.ts"
RUNNER="apps/api/src/modules/simulation/tournament-runner.ts"
ADAPTER="apps/api/src/modules/simulation/sportsos-adapter.ts"
TEST="apps/api/test/simulation-provisioner.test.ts"
RUNNER_SCRIPT="scripts/test-simulation-provisioner.sh"
PACKAGE="package.json"

for f in "$MIGRATIONS" "$ROUTES" "$SIM" "$RUNNER" "$ADAPTER" "$PACKAGE"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'createSportsOSSimulationAdapter' "$ADAPTER"; then
  echo "Validation Platform 4.3 adapter was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/4.4-${STAMP}"
mkdir -p "$BACKUP_DIR"

for f in "$MIGRATIONS" "$ROUTES" "$PACKAGE"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

node <<'NODE'
const fs = require("fs");
const path = "apps/api/src/infrastructure/migrations.ts";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("CREATE TABLE IF NOT EXISTS simulation_runs")) {
  const marker = "CREATE TABLE IF NOT EXISTS game_action_requests";
  const idx = text.indexOf(marker);

  if (idx < 0) {
    throw new Error("Could not locate game_action_requests migration");
  }

  const stmtEnd = text.indexOf(") ENGINE=InnoDB`);", idx);
  if (stmtEnd < 0) {
    throw new Error("Could not locate end of game_action_requests migration");
  }

  const insertAt = stmtEnd + ") ENGINE=InnoDB`);".length;

  const migration = `

  await pool.execute(\`CREATE TABLE IF NOT EXISTS simulation_runs (
    id VARCHAR(64) NOT NULL PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    season_id BIGINT UNSIGNED NOT NULL,
    seed BIGINT NOT NULL,
    config_json LONGTEXT NOT NULL,
    status ENUM('PROVISIONED','RUNNING','COMPLETED','FAILED','CLEANED') NOT NULL DEFAULT 'PROVISIONED',
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    started_at DATETIME(3) NULL,
    completed_at DATETIME(3) NULL,
    cleaned_at DATETIME(3) NULL,
    INDEX idx_simulation_runs_org_created (organization_id, created_at),
    CONSTRAINT fk_simulation_runs_org
      FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT fk_simulation_runs_season
      FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE CASCADE
  ) ENGINE=InnoDB\`);

  await pool.execute(\`CREATE TABLE IF NOT EXISTS simulation_game_bindings (
    run_id VARCHAR(64) NOT NULL,
    simulated_game_id INT UNSIGNED NOT NULL,
    game_id BIGINT UNSIGNED NOT NULL,
    organization_id BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (run_id, simulated_game_id),
    UNIQUE KEY uq_simulation_binding_game (game_id),
    INDEX idx_simulation_bindings_org (organization_id),
    CONSTRAINT fk_simulation_bindings_run
      FOREIGN KEY (run_id) REFERENCES simulation_runs(id) ON DELETE CASCADE,
    CONSTRAINT fk_simulation_bindings_game
      FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    CONSTRAINT fk_simulation_bindings_org
      FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
  ) ENGINE=InnoDB\`);`;

  text = text.slice(0, insertAt) + migration + text.slice(insertAt);
}

fs.writeFileSync(path, text);
NODE

cat > "$PROVISIONER" <<'EOF'
import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { createGame } from "../games/repository.js";
import {
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  type TournamentSimulationConfig,
} from "./tournament-simulator.js";
import {
  createSportsOSSimulationAdapter,
  type SportsOSSimulationGameBinding,
} from "./sportsos-adapter.js";
import { runTournamentSimulation } from "./tournament-runner.js";

export type SimulationRunStatus =
  | "PROVISIONED"
  | "RUNNING"
  | "COMPLETED"
  | "FAILED"
  | "CLEANED";

export interface ProvisionSimulationRunInput {
  runId: string;
  organizationId: number;
  seasonId: number;
  actorUserId: string;
  config?: Partial<TournamentSimulationConfig>;
}

export interface ProvisionedSimulationRun {
  runId: string;
  organizationId: number;
  seasonId: number;
  status: SimulationRunStatus;
  config: TournamentSimulationConfig;
  bindings: SportsOSSimulationGameBinding[];
}

export interface ExecuteSimulationRunResult {
  runId: string;
  status: SimulationRunStatus;
  games: number;
  succeeded: number;
  failed: number;
  processedEvents: number;
  durationMs: number;
}

function normalizeRunId(value: string): string {
  const normalized = value
    .trim()
    .replace(/[^A-Za-z0-9._:-]/g, "-")
    .slice(0, 64);

  if (normalized.length < 4) {
    throw new Error("Simulation runId must contain at least four safe characters");
  }

  return normalized;
}

async function validateSimulationScope(
  organizationId: number,
  seasonId: number,
): Promise<void> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT s.id
     FROM seasons s
     WHERE s.id = ?
       AND s.organization_id = ?
     LIMIT 1`,
    [seasonId, organizationId],
  );

  if (!rows[0]) {
    throw new Error(
      "Simulation season was not found in the requested organization",
    );
  }
}

export async function provisionSimulationRun(
  input: ProvisionSimulationRunInput,
): Promise<ProvisionedSimulationRun> {
  const runId = normalizeRunId(input.runId);
  const config = normalizeTournamentSimulationConfig(input.config ?? {});

  if (!Number.isInteger(input.organizationId) || input.organizationId <= 0) {
    throw new Error("Simulation organizationId must be a positive integer");
  }

  if (!Number.isInteger(input.seasonId) || input.seasonId <= 0) {
    throw new Error("Simulation seasonId must be a positive integer");
  }

  await validateSimulationScope(input.organizationId, input.seasonId);

  const [existing] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM simulation_runs
     WHERE id = ?
     LIMIT 1`,
    [runId],
  );

  if (existing[0]) {
    throw new Error(`Simulation run ${runId} already exists`);
  }

  await pool.execute<ResultSetHeader>(
    `INSERT INTO simulation_runs
      (id, organization_id, season_id, seed, config_json, status, created_by)
     VALUES (?, ?, ?, ?, ?, 'PROVISIONED', ?)`,
    [
      runId,
      input.organizationId,
      input.seasonId,
      config.seed,
      JSON.stringify(config),
      Number(input.actorUserId),
    ],
  );

  const plan = generateTournamentPlan(config);
  const bindings: SportsOSSimulationGameBinding[] = [];
  const createdGameIds: number[] = [];

  try {
    for (const simulatedGame of plan.games) {
      const homeTeam = plan.teams.find(
        (team) => team.id === simulatedGame.homeTeamId,
      );
      const awayTeam = plan.teams.find(
        (team) => team.id === simulatedGame.awayTeamId,
      );

      if (!homeTeam || !awayTeam) {
        throw new Error(
          `Simulation plan contains an invalid team binding for game ${simulatedGame.id}`,
        );
      }

      const scheduledStart = new Date(
        Date.now() + simulatedGame.scheduledOffsetMinutes * 60_000,
      ).toISOString();

      const game = await createGame({
        organizationId: input.organizationId,
        seasonId: input.seasonId,
        homeTeamId: null,
        homeExternalName: `[SIM] ${homeTeam.name}`,
        awayTeamId: null,
        awayExternalName: `[SIM] ${awayTeam.name}`,
        scheduledStart,
        timezone: "America/Chicago",
        venue: `[SIM] Rink ${simulatedGame.rink}`,
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        regulationPeriods: config.regulationPeriods,
        regulationPeriodLengthMs: config.periodLengthMs,
        intermissionLengthMs: config.intermissionLengthMs,
        overtimeEnabled: true,
        overtimeLengthMs: 300_000,
        notes: `SIMULATION_RUN:${runId};SIMULATED_GAME:${simulatedGame.id}`,
      });

      createdGameIds.push(game.id);

      const binding: SportsOSSimulationGameBinding = {
        simulatedGameId: simulatedGame.id,
        sportsOSGameId: game.id,
        organizationId: input.organizationId,
      };

      bindings.push(binding);

      await pool.execute(
        `INSERT INTO simulation_game_bindings
          (run_id, simulated_game_id, game_id, organization_id)
         VALUES (?, ?, ?, ?)`,
        [
          runId,
          simulatedGame.id,
          game.id,
          input.organizationId,
        ],
      );
    }
  } catch (error) {
    for (const gameId of createdGameIds.reverse()) {
      await pool.execute("DELETE FROM games WHERE id = ?", [gameId]);
    }

    await pool.execute("DELETE FROM simulation_runs WHERE id = ?", [runId]);
    throw error;
  }

  return {
    runId,
    organizationId: input.organizationId,
    seasonId: input.seasonId,
    status: "PROVISIONED",
    config,
    bindings,
  };
}

interface SimulationRunRow extends RowDataPacket {
  id: string;
  organization_id: number;
  season_id: number;
  seed: number;
  config_json: string;
  status: SimulationRunStatus;
}

interface SimulationBindingRow extends RowDataPacket {
  simulated_game_id: number;
  game_id: number;
  organization_id: number;
}

export async function getProvisionedSimulationRun(
  runIdInput: string,
): Promise<ProvisionedSimulationRun | null> {
  const runId = normalizeRunId(runIdInput);

  const [runs] = await pool.execute<SimulationRunRow[]>(
    `SELECT id, organization_id, season_id, seed, config_json, status
     FROM simulation_runs
     WHERE id = ?
     LIMIT 1`,
    [runId],
  );

  const run = runs[0];
  if (!run) return null;

  const [rows] = await pool.execute<SimulationBindingRow[]>(
    `SELECT simulated_game_id, game_id, organization_id
     FROM simulation_game_bindings
     WHERE run_id = ?
     ORDER BY simulated_game_id`,
    [runId],
  );

  return {
    runId: run.id,
    organizationId: Number(run.organization_id),
    seasonId: Number(run.season_id),
    status: run.status,
    config: normalizeTournamentSimulationConfig(
      JSON.parse(run.config_json) as Partial<TournamentSimulationConfig>,
    ),
    bindings: rows.map((row) => ({
      simulatedGameId: Number(row.simulated_game_id),
      sportsOSGameId: Number(row.game_id),
      organizationId: Number(row.organization_id),
    })),
  };
}

export async function executeProvisionedSimulationRun(
  runIdInput: string,
  actorUserId: string,
  concurrency?: number,
): Promise<ExecuteSimulationRunResult> {
  const run = await getProvisionedSimulationRun(runIdInput);

  if (!run) {
    throw new Error("Simulation run not found");
  }

  if (run.status !== "PROVISIONED" && run.status !== "FAILED") {
    throw new Error(
      `Simulation run ${run.runId} cannot execute from status ${run.status}`,
    );
  }

  await pool.execute(
    `UPDATE simulation_runs
     SET status = 'RUNNING', started_at = CURRENT_TIMESTAMP(3), completed_at = NULL
     WHERE id = ?`,
    [run.runId],
  );

  try {
    const adapter = createSportsOSSimulationAdapter({
      bindings: run.bindings,
      actorUserId,
      runId: run.runId,
    });

    const result = await runTournamentSimulation(
      adapter,
      run.config,
      {
        concurrency: concurrency ?? run.config.rinkCount,
        failFast: false,
      },
    );

    const status: SimulationRunStatus =
      result.failed === 0 ? "COMPLETED" : "FAILED";

    await pool.execute(
      `UPDATE simulation_runs
       SET status = ?, completed_at = CURRENT_TIMESTAMP(3)
       WHERE id = ?`,
      [status, run.runId],
    );

    return {
      runId: run.runId,
      status,
      games: result.games,
      succeeded: result.succeeded,
      failed: result.failed,
      processedEvents: result.processedEvents,
      durationMs: result.durationMs,
    };
  } catch (error) {
    await pool.execute(
      `UPDATE simulation_runs
       SET status = 'FAILED', completed_at = CURRENT_TIMESTAMP(3)
       WHERE id = ?`,
      [run.runId],
    );
    throw error;
  }
}

export async function cleanupSimulationRun(
  runIdInput: string,
): Promise<{ runId: string; deletedGames: number }> {
  const runId = normalizeRunId(runIdInput);

  const [rows] = await pool.execute<SimulationBindingRow[]>(
    `SELECT simulated_game_id, game_id, organization_id
     FROM simulation_game_bindings
     WHERE run_id = ?
     ORDER BY simulated_game_id`,
    [runId],
  );

  if (rows.length === 0) {
    const [existing] = await pool.execute<RowDataPacket[]>(
      "SELECT id FROM simulation_runs WHERE id = ? LIMIT 1",
      [runId],
    );

    if (!existing[0]) {
      throw new Error("Simulation run not found");
    }
  }

  let deletedGames = 0;

  for (const row of rows) {
    const [result] = await pool.execute<ResultSetHeader>(
      "DELETE FROM games WHERE id = ?",
      [Number(row.game_id)],
    );
    deletedGames += result.affectedRows;
  }

  await pool.execute(
    `UPDATE simulation_runs
     SET status = 'CLEANED', cleaned_at = CURRENT_TIMESTAMP(3)
     WHERE id = ?`,
    [runId],
  );

  return { runId, deletedGames };
}
EOF

node <<'NODE'
const fs = require("fs");
const path = "apps/api/src/modules/simulation/routes.ts";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("provisionSimulationRun")) {
  const importAnchor =
`import {
  generateGameEventStream,
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  summarizeTournamentSimulation,
} from "./tournament-simulator.js";`;

  if (!text.includes(importAnchor)) {
    throw new Error("Tournament simulator import block not found");
  }

  text = text.replace(
    importAnchor,
`${importAnchor}
import {
  cleanupSimulationRun,
  executeProvisionedSimulationRun,
  getProvisionedSimulationRun,
  provisionSimulationRun,
} from "./provisioner.js";
import { ROLES } from "../auth/index.js";`,
  );
}

if (!text.includes('"/simulation/runs/provision"')) {
  const end = text.lastIndexOf("}");
  if (end < 0) throw new Error("Simulation routes end not found");

  const routes = `
  app.post("/simulation/runs/provision", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation provisioning requires system administrator access",
      });
    }

    const body = request.body as {
      runId?: string;
      organizationId?: number;
      seasonId?: number;
      config?: Record<string, unknown>;
    };

    if (
      typeof body.runId !== "string" ||
      !Number.isInteger(Number(body.organizationId)) ||
      !Number.isInteger(Number(body.seasonId))
    ) {
      return reply.code(400).send({ error: "Invalid simulation provisioning request" });
    }

    return provisionSimulationRun({
      runId: body.runId,
      organizationId: Number(body.organizationId),
      seasonId: Number(body.seasonId),
      actorUserId: identity.sub,
      config: body.config ?? {},
    });
  });

  app.get("/simulation/runs/:runId", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation access requires system administrator access",
      });
    }

    const runId = (request.params as { runId: string }).runId;
    const run = await getProvisionedSimulationRun(runId);

    if (!run) return reply.code(404).send({ error: "Simulation run not found" });
    return run;
  });

  app.post("/simulation/runs/:runId/execute", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation execution requires system administrator access",
      });
    }

    const runId = (request.params as { runId: string }).runId;
    const body = (request.body ?? {}) as { concurrency?: number };

    return executeProvisionedSimulationRun(
      runId,
      identity.sub,
      body.concurrency,
    );
  });

  app.delete("/simulation/runs/:runId", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation cleanup requires system administrator access",
      });
    }

    const runId = (request.params as { runId: string }).runId;
    return cleanupSimulationRun(runId);
  });
`;

  text = text.slice(0, end) + routes + text.slice(end);
}

fs.writeFileSync(path, text);
NODE

cat > "$TEST" <<'EOF'
import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const createGame = vi.fn();
const runTournamentSimulation = vi.fn();
const createSportsOSSimulationAdapter = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
  },
}));

vi.mock("../src/modules/games/repository.js", () => ({
  createGame,
}));

vi.mock("../src/modules/simulation/tournament-runner.js", () => ({
  runTournamentSimulation,
}));

vi.mock("../src/modules/simulation/sportsos-adapter.js", () => ({
  createSportsOSSimulationAdapter,
}));

const {
  cleanupSimulationRun,
  executeProvisionedSimulationRun,
  provisionSimulationRun,
} = await import("../src/modules/simulation/provisioner.js");

beforeEach(() => {
  vi.clearAllMocks();
});

describe("isolated simulation provisioning", () => {
  it("creates only external-team simulation games and explicit bindings", async () => {
    poolExecute
      .mockResolvedValueOnce([[{ id: 5 }]])
      .mockResolvedValueOnce([[]])
      .mockResolvedValue({ affectedRows: 1 });

    let nextGameId = 1000;
    createGame.mockImplementation(async (input) => ({
      id: nextGameId++,
      organizationId: input.organizationId,
      ...input,
    }));

    const result = await provisionSimulationRun({
      runId: "stress-001",
      organizationId: 9,
      seasonId: 5,
      actorUserId: "7",
      config: {
        seed: 42,
        rinkCount: 2,
        teamCount: 8,
        gameCount: 6,
      },
    });

    expect(result.bindings).toHaveLength(6);
    expect(createGame).toHaveBeenCalledTimes(6);

    for (const [input] of createGame.mock.calls) {
      expect(input.homeTeamId).toBeNull();
      expect(input.awayTeamId).toBeNull();
      expect(input.homeExternalName).toMatch(/^\[SIM\] /);
      expect(input.awayExternalName).toMatch(/^\[SIM\] /);
      expect(input.notes).toContain("SIMULATION_RUN:stress-001");
    }

    const bindingCalls = poolExecute.mock.calls.filter(([sql]) =>
      String(sql).includes("INSERT INTO simulation_game_bindings"),
    );

    expect(bindingCalls).toHaveLength(6);
  });

  it("refuses to provision against a season outside the organization", async () => {
    poolExecute.mockResolvedValueOnce([[]]);

    await expect(
      provisionSimulationRun({
        runId: "bad-scope",
        organizationId: 9,
        seasonId: 999,
        actorUserId: "7",
      }),
    ).rejects.toThrow(
      "Simulation season was not found in the requested organization",
    );

    expect(createGame).not.toHaveBeenCalled();
  });

  it("executes a provisioned run through the SportsOS adapter", async () => {
    const config = {
      name: "Test",
      seed: 42,
      rinkCount: 2,
      teamCount: 8,
      gameCount: 2,
      playersPerTeam: 15,
      regulationPeriods: 3,
      periodLengthMs: 900000,
      intermissionLengthMs: 600000,
    };

    poolExecute
      .mockResolvedValueOnce([
        [
          {
            id: "stress-002",
            organization_id: 9,
            season_id: 5,
            seed: 42,
            config_json: JSON.stringify(config),
            status: "PROVISIONED",
          },
        ],
      ])
      .mockResolvedValueOnce([
        [
          { simulated_game_id: 1, game_id: 1001, organization_id: 9 },
          { simulated_game_id: 2, game_id: 1002, organization_id: 9 },
        ],
      ])
      .mockResolvedValue({ affectedRows: 1 });

    const fakeAdapter = {};
    createSportsOSSimulationAdapter.mockReturnValue(fakeAdapter);

    runTournamentSimulation.mockResolvedValue({
      games: 2,
      succeeded: 2,
      failed: 0,
      processedEvents: 80,
      durationMs: 125,
      results: [],
    });

    const result = await executeProvisionedSimulationRun(
      "stress-002",
      "7",
      2,
    );

    expect(createSportsOSSimulationAdapter).toHaveBeenCalledWith({
      bindings: [
        { simulatedGameId: 1, sportsOSGameId: 1001, organizationId: 9 },
        { simulatedGameId: 2, sportsOSGameId: 1002, organizationId: 9 },
      ],
      actorUserId: "7",
      runId: "stress-002",
    });

    expect(runTournamentSimulation).toHaveBeenCalledWith(
      fakeAdapter,
      expect.objectContaining({
        seed: 42,
        gameCount: 2,
      }),
      {
        concurrency: 2,
        failFast: false,
      },
    );

    expect(result.status).toBe("COMPLETED");
  });

  it("cleanup deletes only explicitly bound simulation game ids", async () => {
    poolExecute
      .mockResolvedValueOnce([
        [
          { simulated_game_id: 1, game_id: 1001, organization_id: 9 },
          { simulated_game_id: 2, game_id: 1002, organization_id: 9 },
        ],
      ])
      .mockResolvedValueOnce({ affectedRows: 1 })
      .mockResolvedValueOnce({ affectedRows: 1 })
      .mockResolvedValueOnce({ affectedRows: 1 });

    const result = await cleanupSimulationRun("stress-003");

    expect(result.deletedGames).toBe(2);

    expect(poolExecute).toHaveBeenCalledWith(
      "DELETE FROM games WHERE id = ?",
      [1001],
    );
    expect(poolExecute).toHaveBeenCalledWith(
      "DELETE FROM games WHERE id = ?",
      [1002],
    );

    expect(
      poolExecute.mock.calls.some(([sql]) =>
        String(sql).includes("DELETE FROM games WHERE organization_id"),
      ),
    ).toBe(false);
  });
});
EOF

cat > "$RUNNER_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=============================================="
echo " SportsOS Next - Simulation Provisioning Gate"
echo "=============================================="

npm run test --workspace=@sportsos/api -- test/simulation-provisioner.test.ts
EOF

chmod +x "$RUNNER_SCRIPT"

node <<'NODE'
const fs = require("fs");
const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts ??= {};
pkg.scripts["test:simulation-provisioner"] =
  "./scripts/test-simulation-provisioner.sh";

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo
echo "============================================="
echo " SportsOS Next - Validation Platform 4.4"
echo " Isolated Simulation Provisioning + Execution"
echo "============================================="
echo
echo "Created:"
echo "  $PROVISIONER"
echo "  $TEST"
echo "  $RUNNER_SCRIPT"
echo
echo "Modified:"
echo "  $MIGRATIONS"
echo "  $ROUTES"
echo "  $PACKAGE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "New tables:"
echo "  simulation_runs"
echo "  simulation_game_bindings"
echo
echo "New admin-only API:"
echo "  POST   /simulation/runs/provision"
echo "  GET    /simulation/runs/:runId"
echo "  POST   /simulation/runs/:runId/execute"
echo "  DELETE /simulation/runs/:runId"
echo
echo "Safety:"
echo "  explicit organization + season scope"
echo "  simulated teams use external names only"
echo "  every created game gets a binding row"
echo "  cleanup deletes ONLY bound game ids"
echo "  system-admin access required"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run test:simulation-provisioner"
