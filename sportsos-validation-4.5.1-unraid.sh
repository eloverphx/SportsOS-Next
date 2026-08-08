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

PROVISIONER="apps/api/src/modules/simulation/provisioner.ts"
QUALIFIER="apps/api/src/modules/simulation/qualification.ts"
ROUTES="apps/api/src/modules/simulation/routes.ts"
TEST="apps/api/test/simulation-qualification.test.ts"
RUNNER_SCRIPT="scripts/test-simulation-qualification.sh"
PACKAGE="package.json"

for f in "$PROVISIONER" "$ROUTES" "$PACKAGE"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'executeProvisionedSimulationRun' "$PROVISIONER"; then
  echo "Validation Platform 4.4 provisioning was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/4.5.1-${STAMP}"
mkdir -p "$BACKUP_DIR"

for f in "$PROVISIONER" "$ROUTES" "$PACKAGE"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

cat > "$QUALIFIER" <<'EOF'
import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import {
  cleanupSimulationRun,
  executeProvisionedSimulationRun,
  getProvisionedSimulationRun,
  provisionSimulationRun,
  type ProvisionSimulationRunInput,
} from "./provisioner.js";

export interface SimulationQualificationOptions
  extends ProvisionSimulationRunInput {
  concurrency?: number;
  cleanupOnPass?: boolean;
}

export interface SimulationQualificationGameResult {
  simulatedGameId: number;
  gameId: number;
  status: string;
  homeScore: number;
  awayScore: number;
  events: number;
  goals: number;
  penalties: number;
  passed: boolean;
  failures: string[];
}

export interface SimulationQualificationReport {
  runId: string;
  startedAt: string;
  finishedAt: string;
  durationMs: number;
  overall: "PASS" | "FAIL";
  execution: {
    status: string;
    games: number;
    succeeded: number;
    failed: number;
    processedEvents: number;
    durationMs: number;
  };
  verification: {
    gamesExpected: number;
    gamesVerified: number;
    gamesPassed: number;
    gamesFailed: number;
    events: number;
    goals: number;
    penalties: number;
  };
  games: SimulationQualificationGameResult[];
  cleanup: {
    requested: boolean;
    performed: boolean;
    deletedGames: number;
  };
}

interface VerificationRow extends RowDataPacket {
  game_id: number;
  simulated_game_id: number;
  status: string;
  home_score: number;
  away_score: number;
  event_count: number;
  goal_count: number;
  penalty_count: number;
}

async function verifySimulationRun(
  runId: string,
): Promise<SimulationQualificationGameResult[]> {
  const [rows] = await pool.execute<VerificationRow[]>(
    `SELECT
       b.game_id,
       b.simulated_game_id,
       g.status,
       g.home_score,
       g.away_score,
       COUNT(ge.id) AS event_count,
       SUM(CASE WHEN ge.type = 'GOAL' AND ge.voided_at IS NULL THEN 1 ELSE 0 END) AS goal_count,
       SUM(CASE WHEN ge.type = 'PENALTY' AND ge.voided_at IS NULL THEN 1 ELSE 0 END) AS penalty_count
     FROM simulation_game_bindings b
     JOIN games g ON g.id = b.game_id
     LEFT JOIN game_events ge ON ge.game_id = g.id
     WHERE b.run_id = ?
     GROUP BY
       b.game_id,
       b.simulated_game_id,
       g.status,
       g.home_score,
       g.away_score
     ORDER BY b.simulated_game_id`,
    [runId],
  );

  return rows.map((row) => {
    const failures: string[] = [];
    const homeScore = Number(row.home_score);
    const awayScore = Number(row.away_score);
    const goals = Number(row.goal_count ?? 0);
    const penalties = Number(row.penalty_count ?? 0);
    const events = Number(row.event_count ?? 0);
    const status = String(row.status);

    if (status !== "FINAL") {
      failures.push(`Expected FINAL status, found ${status}`);
    }

    if (homeScore + awayScore !== goals) {
      failures.push(
        `Score/event mismatch: score total ${homeScore + awayScore}, goal events ${goals}`,
      );
    }

    if (events < goals + penalties) {
      failures.push(
        `Event count ${events} is lower than goals + penalties ${goals + penalties}`,
      );
    }

    return {
      simulatedGameId: Number(row.simulated_game_id),
      gameId: Number(row.game_id),
      status,
      homeScore,
      awayScore,
      events,
      goals,
      penalties,
      passed: failures.length === 0,
      failures,
    };
  });
}

export async function qualifySimulationRun(
  options: SimulationQualificationOptions,
): Promise<SimulationQualificationReport> {
  const started = Date.now();

  const provisioned = await provisionSimulationRun(options);

  const execution = await executeProvisionedSimulationRun(
    provisioned.runId,
    options.actorUserId,
    options.concurrency,
  );

  const games = await verifySimulationRun(provisioned.runId);

  const expectedGames = provisioned.bindings.length;
  const gamesPassed = games.filter((game) => game.passed).length;
  const gamesFailed = games.length - gamesPassed;

  let overall: "PASS" | "FAIL" = "PASS";

  if (
    execution.status !== "COMPLETED" ||
    execution.failed !== 0 ||
    execution.succeeded !== expectedGames ||
    games.length !== expectedGames ||
    gamesFailed !== 0
  ) {
    overall = "FAIL";
  }

  let deletedGames = 0;
  let cleanupPerformed = false;

  if (overall === "PASS" && options.cleanupOnPass) {
    const cleanup = await cleanupSimulationRun(provisioned.runId);
    deletedGames = cleanup.deletedGames;
    cleanupPerformed = true;

    if (deletedGames !== expectedGames) {
      overall = "FAIL";
    }
  }

  const finished = Date.now();

  return {
    runId: provisioned.runId,
    startedAt: new Date(started).toISOString(),
    finishedAt: new Date(finished).toISOString(),
    durationMs: finished - started,
    overall,
    execution: {
      status: execution.status,
      games: execution.games,
      succeeded: execution.succeeded,
      failed: execution.failed,
      processedEvents: execution.processedEvents,
      durationMs: execution.durationMs,
    },
    verification: {
      gamesExpected: expectedGames,
      gamesVerified: games.length,
      gamesPassed,
      gamesFailed,
      events: games.reduce((sum, game) => sum + game.events, 0),
      goals: games.reduce((sum, game) => sum + game.goals, 0),
      penalties: games.reduce((sum, game) => sum + game.penalties, 0),
    },
    games,
    cleanup: {
      requested: Boolean(options.cleanupOnPass),
      performed: cleanupPerformed,
      deletedGames,
    },
  };
}
EOF

node <<'NODE'
const fs = require("fs");
const path = "apps/api/src/modules/simulation/routes.ts";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("qualifySimulationRun")) {
  const importAnchor =
`import {
  cleanupSimulationRun,
  executeProvisionedSimulationRun,
  getProvisionedSimulationRun,
  provisionSimulationRun,
} from "./provisioner.js";`;

  if (!text.includes(importAnchor)) {
    throw new Error("Provisioner import block not found");
  }

  text = text.replace(
    importAnchor,
`${importAnchor}
import { qualifySimulationRun } from "./qualification.js";`,
  );
}

if (!text.includes('"/simulation/qualification/run"')) {
  const end = text.lastIndexOf("}");
  if (end < 0) throw new Error("Could not locate end of simulation routes");

  const route = `
  app.post("/simulation/qualification/run", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Simulation qualification requires system administrator access",
      });
    }

    const body = request.body as {
      runId?: string;
      organizationId?: number;
      seasonId?: number;
      concurrency?: number;
      cleanupOnPass?: boolean;
      config?: Record<string, unknown>;
    };

    if (
      typeof body.runId !== "string" ||
      !Number.isInteger(Number(body.organizationId)) ||
      !Number.isInteger(Number(body.seasonId))
    ) {
      return reply.code(400).send({
        error: "Invalid simulation qualification request",
      });
    }

    return qualifySimulationRun({
      runId: body.runId,
      organizationId: Number(body.organizationId),
      seasonId: Number(body.seasonId),
      actorUserId: identity.sub,
      concurrency:
        body.concurrency === undefined
          ? undefined
          : Number(body.concurrency),
      cleanupOnPass: body.cleanupOnPass ?? false,
      config: body.config ?? {},
    });
  });
`;

  text = text.slice(0, end) + route + text.slice(end);
}

fs.writeFileSync(path, text);
NODE

cat > "$TEST" <<'EOF'
import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const provisionSimulationRun = vi.fn();
const executeProvisionedSimulationRun = vi.fn();
const cleanupSimulationRun = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
  },
}));

vi.mock("../src/modules/simulation/provisioner.js", () => ({
  provisionSimulationRun,
  executeProvisionedSimulationRun,
  cleanupSimulationRun,
  getProvisionedSimulationRun: vi.fn(),
}));

const { qualifySimulationRun } = await import(
  "../src/modules/simulation/qualification.js"
);

beforeEach(() => {
  vi.clearAllMocks();

  provisionSimulationRun.mockResolvedValue({
    runId: "qualification-001",
    organizationId: 9,
    seasonId: 5,
    status: "PROVISIONED",
    config: {
      name: "Qualification",
      seed: 42,
      rinkCount: 1,
      teamCount: 2,
      gameCount: 1,
      playersPerTeam: 15,
      regulationPeriods: 3,
      periodLengthMs: 900000,
      intermissionLengthMs: 600000,
    },
    bindings: [
      {
        simulatedGameId: 1,
        sportsOSGameId: 1001,
        organizationId: 9,
      },
    ],
  });

  executeProvisionedSimulationRun.mockResolvedValue({
    runId: "qualification-001",
    status: "COMPLETED",
    games: 1,
    succeeded: 1,
    failed: 0,
    processedEvents: 44,
    durationMs: 100,
  });
});

describe("live simulation qualification", () => {
  it("passes a completed run whose persisted score matches goal events", async () => {
    poolExecute.mockResolvedValueOnce([
      [
        {
          game_id: 1001,
          simulated_game_id: 1,
          status: "FINAL",
          home_score: 3,
          away_score: 2,
          event_count: 8,
          goal_count: 5,
          penalty_count: 3,
        },
      ],
    ]);

    const report = await qualifySimulationRun({
      runId: "qualification-001",
      organizationId: 9,
      seasonId: 5,
      actorUserId: "7",
      concurrency: 1,
      cleanupOnPass: false,
      config: {
        rinkCount: 1,
        teamCount: 2,
        gameCount: 1,
      },
    });

    expect(report.overall).toBe("PASS");
    expect(report.verification).toEqual(
      expect.objectContaining({
        gamesExpected: 1,
        gamesVerified: 1,
        gamesPassed: 1,
        gamesFailed: 0,
        goals: 5,
        penalties: 3,
      }),
    );
  });

  it("fails when persisted final score disagrees with goal events", async () => {
    poolExecute.mockResolvedValueOnce([
      [
        {
          game_id: 1001,
          simulated_game_id: 1,
          status: "FINAL",
          home_score: 4,
          away_score: 2,
          event_count: 8,
          goal_count: 5,
          penalty_count: 3,
        },
      ],
    ]);

    const report = await qualifySimulationRun({
      runId: "qualification-001",
      organizationId: 9,
      seasonId: 5,
      actorUserId: "7",
    });

    expect(report.overall).toBe("FAIL");
    expect(report.games[0]?.failures[0]).toContain("Score/event mismatch");
  });

  it("fails when the game never reaches FINAL", async () => {
    poolExecute.mockResolvedValueOnce([
      [
        {
          game_id: 1001,
          simulated_game_id: 1,
          status: "LIVE",
          home_score: 3,
          away_score: 2,
          event_count: 8,
          goal_count: 5,
          penalty_count: 3,
        },
      ],
    ]);

    const report = await qualifySimulationRun({
      runId: "qualification-001",
      organizationId: 9,
      seasonId: 5,
      actorUserId: "7",
    });

    expect(report.overall).toBe("FAIL");
    expect(report.games[0]?.failures).toContain(
      "Expected FINAL status, found LIVE",
    );
  });

  it("cleans up only after a successful qualification when requested", async () => {
    poolExecute.mockResolvedValueOnce([
      [
        {
          game_id: 1001,
          simulated_game_id: 1,
          status: "FINAL",
          home_score: 2,
          away_score: 1,
          event_count: 4,
          goal_count: 3,
          penalty_count: 1,
        },
      ],
    ]);

    cleanupSimulationRun.mockResolvedValue({
      runId: "qualification-001",
      deletedGames: 1,
    });

    const report = await qualifySimulationRun({
      runId: "qualification-001",
      organizationId: 9,
      seasonId: 5,
      actorUserId: "7",
      cleanupOnPass: true,
    });

    expect(report.overall).toBe("PASS");
    expect(cleanupSimulationRun).toHaveBeenCalledWith("qualification-001");
    expect(report.cleanup).toEqual({
      requested: true,
      performed: true,
      deletedGames: 1,
    });
  });

  it("does not automatically clean up a failed qualification", async () => {
    poolExecute.mockResolvedValueOnce([
      [
        {
          game_id: 1001,
          simulated_game_id: 1,
          status: "LIVE",
          home_score: 2,
          away_score: 1,
          event_count: 4,
          goal_count: 3,
          penalty_count: 1,
        },
      ],
    ]);

    const report = await qualifySimulationRun({
      runId: "qualification-001",
      organizationId: 9,
      seasonId: 5,
      actorUserId: "7",
      cleanupOnPass: true,
    });

    expect(report.overall).toBe("FAIL");
    expect(cleanupSimulationRun).not.toHaveBeenCalled();
    expect(report.cleanup.performed).toBe(false);
  });
});
EOF

cat > "$RUNNER_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=============================================="
echo " SportsOS Next - Live Simulation Qualification"
echo "=============================================="

npm run test --workspace=@sportsos/api -- test/simulation-qualification.test.ts
EOF

chmod +x "$RUNNER_SCRIPT"

node <<'NODE'
const fs = require("fs");
const path = "package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts ??= {};
pkg.scripts["test:simulation-qualification"] =
  "./scripts/test-simulation-qualification.sh";

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo
echo "============================================="
echo " SportsOS Validation Platform 4.5.1"
echo " Controlled Live Execution Qualification"
echo "============================================="
echo
echo "Created:"
echo "  $QUALIFIER"
echo "  $TEST"
echo "  $RUNNER_SCRIPT"
echo
echo "Modified:"
echo "  $ROUTES"
echo "  $PACKAGE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "New admin-only endpoint:"
echo "  POST /simulation/qualification/run"
echo
echo "Qualification verifies:"
echo "  provisioned game count"
echo "  execution success/failure"
echo "  FINAL status"
echo "  persisted score == non-voided GOAL event count"
echo "  event count >= goals + penalties"
echo "  cleanup only after PASS when requested"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run test:simulation-qualification"
