import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const applyGameScoringAction = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
  },
}));

vi.mock("../src/modules/games/repository.js", () => ({
  applyGameScoringAction,
}));

const { processAutomaticLifecycleTransitions } = await import(
  "../src/modules/games/runtime-supervisor.js"
);

beforeEach(() => {
  vi.clearAllMocks();
});

describe("automatic multi-game lifecycle supervision", () => {
  it("starts intermissions for multiple completed early regulation periods", async () => {
    poolExecute
      .mockResolvedValueOnce([
        [
          { id: 11, period: 1 },
          { id: 22, period: 2 },
        ],
      ])
      .mockResolvedValueOnce([[]]);

    applyGameScoringAction.mockResolvedValue({
      game: {},
      applied: true,
    });

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 2,
      periodsPrepared: 0,
    });

    expect(applyGameScoringAction).toHaveBeenCalledWith(
      11,
      { action: "startIntermission" },
      "runtime:period-end:11:1",
    );
    expect(applyGameScoringAction).toHaveBeenCalledWith(
      22,
      { action: "startIntermission" },
      "runtime:period-end:22:2",
    );
  });

  it("prepares next regulation periods after intermission expiration", async () => {
    poolExecute
      .mockResolvedValueOnce([[]])
      .mockResolvedValueOnce([
        [
          { id: 31, period: 1 },
          { id: 32, period: 2 },
        ],
      ]);

    applyGameScoringAction.mockResolvedValue({
      game: {},
      applied: true,
    });

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 0,
      periodsPrepared: 2,
    });

    expect(applyGameScoringAction).toHaveBeenCalledWith(
      31,
      { action: "nextPeriod" },
      "runtime:intermission-complete:31:1",
    );
    expect(applyGameScoringAction).toHaveBeenCalledWith(
      32,
      { action: "nextPeriod" },
      "runtime:intermission-complete:32:2",
    );
  });

  it("uses database eligibility rules that leave regulation-end decisions manual", async () => {
    poolExecute.mockResolvedValueOnce([[]]).mockResolvedValueOnce([[]]);

    await processAutomaticLifecycleTransitions();

    const firstSql = String(poolExecute.mock.calls[0]?.[0] ?? "");
    const secondSql = String(poolExecute.mock.calls[1]?.[0] ?? "");

    expect(firstSql).toContain("period < regulation_periods");
    expect(secondSql).toContain("period < regulation_periods");
    expect(firstSql).toContain("game_phase = 'REGULATION'");
    expect(secondSql).toContain("game_phase = 'INTERMISSION'");
  });

  it("does not count idempotent replays as new transitions", async () => {
    poolExecute
      .mockResolvedValueOnce([[{ id: 41, period: 1 }]])
      .mockResolvedValueOnce([[]]);

    applyGameScoringAction.mockResolvedValue(null);

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 0,
      periodsPrepared: 0,
    });
  });
});
