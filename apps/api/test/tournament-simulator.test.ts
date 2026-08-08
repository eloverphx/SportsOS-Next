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
