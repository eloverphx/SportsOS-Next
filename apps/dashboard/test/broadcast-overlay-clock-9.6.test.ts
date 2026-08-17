import { describe, expect, it } from "vitest";
import {
  deriveSmoothedRemainingMs,
  formatOverlayClock,
} from "../lib/broadcast-overlay-clock";

describe("Milestone 9.6 overlay clock smoothing", () => {
  it("holds a paused authoritative clock steady", () => {
    expect(
      deriveSmoothedRemainingMs(
        {
          remainingMs: 120000,
          running: false,
          capturedAtMs: 1000,
        },
        9000,
      ),
    ).toBe(120000);
  });

  it("subtracts elapsed wall time while the clock is running", () => {
    expect(
      deriveSmoothedRemainingMs(
        {
          remainingMs: 120000,
          running: true,
          capturedAtMs: 1000,
        },
        3500,
      ),
    ).toBe(117500);
  });

  it("never displays a negative clock", () => {
    expect(
      deriveSmoothedRemainingMs(
        {
          remainingMs: 1000,
          running: true,
          capturedAtMs: 0,
        },
        5000,
      ),
    ).toBe(0);
  });

  it("formats normal time as minutes and seconds", () => {
    expect(formatOverlayClock(125000)).toBe("2:05");
  });

  it("formats under one minute with tenths", () => {
    expect(formatOverlayClock(59700)).toBe("59.7");
    expect(formatOverlayClock(9400)).toBe("9.4");
  });

  it("renders zero safely", () => {
    expect(formatOverlayClock(0)).toBe("0.0");
  });
});
