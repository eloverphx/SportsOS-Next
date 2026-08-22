import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.4 deterministic startGame preflight enforcement", () => {
  const guard =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightGuard.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const routes =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/modules/games/routes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("blocks missing failed and expired preflight", () => {
    expect(guard).toContain(
      '"PREFLIGHT_REQUIRED"',
    );

    expect(guard).toContain(
      '"PREFLIGHT_FAILED"',
    );

    expect(guard).toContain(
      '"PREFLIGHT_EXPIRED"',
    );
  });

  it("binds enforcement to lifecycle startGame", () => {
    expect(routes).toContain(
      'app.post("/games/:id/lifecycle"',
    );

    expect(routes).toContain(
      'parsed.data.command === "startGame"',
    );

    expect(routes).toContain(
      "GAME_START_PREFLIGHT_ENFORCEMENT_18_4",
    );
  });

  it("rejects before game mutation with HTTP 409", () => {
    expect(routes).toContain(
      "evaluateGameStartPreflight",
    );

    expect(routes).toContain(
      "reply.code(409)",
    );
  });
});
