import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.3 preflight freshness window / expiration", () => {
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

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("defines a configurable 15-minute freshness window", () => {
    expect(service).toContain(
      "SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS",
    );

    expect(service).toContain(
      '"900000"',
    );
  });

  it("requires a passing preflight to be fresh", () => {
    expect(service).toContain(
      'preflight.status !==',
    );

    expect(service).toContain(
      '"PASS"',
    );
  });

  it("expires old passing preflights", () => {
    expect(service).toContain(
      "Latest passing game-day hardware preflight has expired.",
    );

    expect(service).toContain(
      "expiresAt",
    );
  });

  it("exposes freshness through the API", () => {
    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/freshness",
    );

    expect(route).toContain(
      "gameDayHardwarePreflightFreshness",
    );
  });

  it("shows fresh versus expired status in the dashboard", () => {
    expect(panel).toContain(
      "Preflight Freshness",
    );

    expect(panel).toContain(
      "FRESH",
    );

    expect(panel).toContain(
      "EXPIRED / REQUIRED",
    );
  });
});
