import { beforeEach, describe, expect, it } from "vitest";
import {
  classifyEngineGame,
  clearEngineTransitionHistoryForTests,
  getEngineTransitionHistory,
  recordEngineTransition,
  type EngineTelemetryRow,
} from "../src/modules/games/telemetry.js";

function row(overrides: Partial<EngineTelemetryRow> = {}): EngineTelemetryRow {
  return {
    id: 77,
    organizationId: 8,
    homeTeamName: "Lakers",
    awayTeamName: "Storm",
    status: "LIVE",
    gamePhase: "REGULATION",
    period: 1,
    regulationPeriods: 3,
    clockRemainingMs: 300_000,
    clockRunning: false,
    clockStartedAt: null,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    ...overrides,
  };
}

beforeEach(() => {
  clearEngineTransitionHistoryForTests();
});

describe("game engine telemetry classification", () => {
  it("classifies a normal live game as healthy", () => {
    expect(classifyEngineGame(row()).state).toBe("HEALTHY");
  });

  it("flags an early regulation period at zero as transition pending", () => {
    const result = classifyEngineGame(
      row({
        period: 1,
        clockRemainingMs: 0,
      }),
    );

    expect(result.state).toBe("TRANSITION_PENDING");
    expect(result.actionRequired).toContain("begin intermission");
  });

  it("requires an operator decision at the end of regulation", () => {
    const result = classifyEngineGame(
      row({
        period: 3,
        clockRemainingMs: 0,
      }),
    );

    expect(result.state).toBe("OPERATOR_REQUIRED");
    expect(result.actionRequired).toContain("overtime");
  });

  it("requires an operator decision at overtime expiration", () => {
    const result = classifyEngineGame(
      row({
        gamePhase: "OVERTIME",
        period: 4,
        clockRemainingMs: 0,
      }),
    );

    expect(result.state).toBe("OPERATOR_REQUIRED");
  });

  it("flags a running game clock without started_at", () => {
    const result = classifyEngineGame(
      row({
        clockRunning: true,
        clockStartedAt: null,
      }),
    );

    expect(result.state).toBe("WARNING");
    expect(result.warnings.map((warning) => warning.code)).toContain(
      "CLOCK_STARTED_AT_MISSING",
    );
  });

  it("flags simultaneous game and intermission clocks", () => {
    const now = new Date();

    const result = classifyEngineGame(
      row({
        gamePhase: "INTERMISSION",
        clockRunning: true,
        clockStartedAt: now,
        intermissionRemainingMs: 60_000,
        intermissionRunning: true,
        intermissionStartedAt: now,
      }),
    );

    expect(result.state).toBe("WARNING");
    expect(result.warnings.map((warning) => warning.code)).toContain(
      "DUAL_CLOCKS_RUNNING",
    );
  });
});

describe("game engine transition history", () => {
  it("records newest transitions first", () => {
    recordEngineTransition({
      timestamp: "2026-08-08T10:00:00.000Z",
      source: "runtime-supervisor",
      gameId: 1,
      action: "startIntermission",
      outcome: "applied",
    });

    recordEngineTransition({
      timestamp: "2026-08-08T10:01:00.000Z",
      source: "runtime-supervisor",
      gameId: 2,
      action: "nextPeriod",
      outcome: "applied",
    });

    expect(getEngineTransitionHistory()).toEqual([
      expect.objectContaining({ gameId: 2 }),
      expect.objectContaining({ gameId: 1 }),
    ]);
  });

  it("bounds transition history to 100 entries", () => {
    for (let index = 0; index < 125; index += 1) {
      recordEngineTransition({
        source: "system",
        gameId: index,
        action: "test",
        outcome: "applied",
      });
    }

    expect(getEngineTransitionHistory(100)).toHaveLength(100);
  });
});
