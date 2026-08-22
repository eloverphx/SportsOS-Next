import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.6 full emergency override recovery", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightOverride.ts",
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

  const games =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/modules/games/routes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("restores override service operations", () => {
    expect(service).toContain(
      "createGameStartPreflightOverride",
    );

    expect(service).toContain(
      "getActiveGameStartPreflightOverride",
    );

    expect(service).toContain(
      "revokeGameStartPreflightOverride",
    );

    expect(service).toContain(
      "listGameStartPreflightOverrides",
    );
  });

  it("restores override API wiring", () => {
    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/override",
    );

    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/overrides",
    );
  });

  it("restores game-start override lookup", () => {
    expect(games).toContain(
      "GAME_START_PREFLIGHT_OVERRIDE_18_6",
    );

    expect(games).toContain(
      "getActiveGameStartPreflightOverride",
    );
  });
});
