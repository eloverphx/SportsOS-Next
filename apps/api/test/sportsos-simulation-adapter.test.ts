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
