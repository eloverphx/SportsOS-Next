import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.1 game-day hardware preflight", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("requires commissioning game-ready status", () => {
    expect(service).toContain(
      '"GAME_READY"',
    );

    expect(service).toContain(
      '"COMMISSIONING"',
    );
  });

  it("requires fresh heartbeat readiness", () => {
    expect(service).toContain(
      "evaluateScoreboardControlReadiness",
    );

    expect(service).toContain(
      '"HEARTBEAT"',
    );
  });

  it("requires acceptable reliability state", () => {
    expect(service).toContain(
      "listScoreboardReliabilityClassifications",
    );

    expect(service).toContain(
      '"HEALTHY"',
    );

    expect(service).toContain(
      '"WATCH"',
    );
  });

  it("requires a passing hardware self-test", () => {
    expect(service).toContain(
      "latestCommissioningSelfTest",
    );

    expect(service).toContain(
      '"SELF_TEST"',
    );
  });

  it("persists game-specific preflight history", () => {
    expect(service).toContain(
      "game-day-hardware-preflights.json",
    );

    expect(service).toContain(
      "preflightId",
    );
  });

  it("returns conflict when preflight fails", () => {
    expect(route).toContain(
      "reply",
    );

    expect(route).toContain(
      "409",
    );

    expect(route).toContain(
      "Game-day hardware preflight failed.",
    );
  });
});
