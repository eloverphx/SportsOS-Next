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
