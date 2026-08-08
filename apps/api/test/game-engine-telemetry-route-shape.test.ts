import { describe, expect, it } from "vitest";
import {
  classifyEngineGame,
  type EngineTelemetryRow,
} from "../src/modules/games/telemetry.js";

function row(overrides: Partial<EngineTelemetryRow> = {}): EngineTelemetryRow {
  return {
    id: 50,
    organizationId: 9,
    homeTeamName: "Home",
    awayTeamName: "Away",
    status: "LIVE",
    gamePhase: "REGULATION",
    period: 1,
    regulationPeriods: 3,
    clockRemainingMs: 120_000,
    clockRunning: false,
    clockStartedAt: null,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    ...overrides,
  };
}

describe("game engine telemetry dashboard contract", () => {
  it("provides all fields required by the operator dashboard", () => {
    const result = classifyEngineGame(row());

    expect(result).toEqual(
      expect.objectContaining({
        gameId: 50,
        organizationId: 9,
        matchup: "Home vs Away",
        state: "HEALTHY",
        gamePhase: "REGULATION",
        period: 1,
        regulationPeriods: 3,
        clockRemainingMs: 120_000,
        clockRunning: false,
        intermissionRemainingMs: 0,
        intermissionRunning: false,
        actionRequired: null,
        warnings: [],
      }),
    );
  });
});
