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
