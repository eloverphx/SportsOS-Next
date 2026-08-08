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
      .mockResolvedValueOnce([{ affectedRows: 1 }, []])
      .mockResolvedValueOnce([{ affectedRows: 1 }, []])
      .mockResolvedValueOnce([{ affectedRows: 1 }, []]);

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
