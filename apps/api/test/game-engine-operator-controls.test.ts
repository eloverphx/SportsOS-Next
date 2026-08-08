import { describe, expect, it } from "vitest";
import {
  classifyEngineGame,
  type EngineTelemetryRow,
} from "../src/modules/games/telemetry.js";

function row(overrides: Partial<EngineTelemetryRow> = {}): EngineTelemetryRow {
  return {
    id: 88,
    organizationId: 12,
    homeTeamName: "Lakers",
    awayTeamName: "Bears",
    status: "LIVE",
    gamePhase: "REGULATION",
    period: 3,
    regulationPeriods: 3,
    clockRemainingMs: 0,
    clockRunning: false,
    clockStartedAt: null,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    overtimeEnabled: true,
    ...overrides,
  };
}

describe("game engine operator control telemetry", () => {
  it("exposes overtime availability for regulation-end decisions", () => {
    const result = classifyEngineGame(row());

    expect(result.state).toBe("OPERATOR_REQUIRED");
    expect(result.overtimeEnabled).toBe(true);
  });

  it("exposes disabled overtime while still requiring a final decision", () => {
    const result = classifyEngineGame(row({ overtimeEnabled: false }));

    expect(result.state).toBe("OPERATOR_REQUIRED");
    expect(result.overtimeEnabled).toBe(false);
    expect(result.actionRequired).toContain("overtime");
  });

  it("keeps overtime expiration operator-controlled", () => {
    const result = classifyEngineGame(
      row({
        gamePhase: "OVERTIME",
        period: 4,
        overtimeEnabled: true,
      }),
    );

    expect(result.state).toBe("OPERATOR_REQUIRED");
    expect(result.overtimeEnabled).toBe(true);
  });
});
