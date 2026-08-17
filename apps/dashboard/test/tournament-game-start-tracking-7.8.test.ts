import { describe, expect, it } from "vitest";
import {
  computeGameStartTiming,
  formatDelayLabel,
} from "../lib/tournament-game-start-tracking";

describe("Milestone 7.8 delay / actual start tracking", () => {
  const scheduled = "2026-08-16T20:00:00.000Z";

  it("reports not-scheduled when scheduled start is missing", () => {
    const timing = computeGameStartTiming(null, null);

    expect(timing).toMatchObject({
      scheduledStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_SCHEDULED",
    });

    expect(formatDelayLabel(timing)).toBe("Not scheduled");
  });

  it("reports not-started before an actual start exists", () => {
    expect(computeGameStartTiming(scheduled, null)).toMatchObject({
      actualStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_STARTED",
    });
  });

  it("treats a start within 30 seconds as on time", () => {
    const timing = computeGameStartTiming(
      scheduled,
      "2026-08-16T20:00:20.000Z",
    );

    expect(timing.state).toBe("ON_TIME");
    expect(formatDelayLabel(timing)).toBe("On time");
  });

  it("calculates a late start", () => {
    const timing = computeGameStartTiming(
      scheduled,
      "2026-08-16T20:07:30.000Z",
    );

    expect(timing.state).toBe("DELAYED");
    expect(timing.delayMinutes).toBe(7.5);
    expect(formatDelayLabel(timing)).toBe("7.5 min late");
  });

  it("calculates an early start", () => {
    const timing = computeGameStartTiming(
      scheduled,
      "2026-08-16T19:57:00.000Z",
    );

    expect(timing.state).toBe("EARLY");
    expect(timing.delayMinutes).toBe(-3);
    expect(formatDelayLabel(timing)).toBe("3 min early");
  });

  it("rejects invalid timestamps", () => {
    expect(() =>
      computeGameStartTiming("not-a-date", null),
    ).toThrow("Invalid scheduled start timestamp.");

    expect(() =>
      computeGameStartTiming(scheduled, "not-a-date"),
    ).toThrow("Invalid actual start timestamp.");
  });
});
