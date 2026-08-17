import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 7.7 live game state integration", () => {
  it("uses the real lifecycle endpoint and startGame command", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("/games/${encodeURIComponent(gameId)}/lifecycle");
    expect(route).toContain('command: "startGame"');
    expect(route).toContain('method: "POST"');
  });

  it("forwards authentication context", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain('request.headers.get("authorization")');
    expect(route).toContain('request.headers.get("cookie")');
  });

  it("does not forward testing override as server authority", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).not.toContain("testingOverrideEnabled");
    expect(route).not.toContain("x-sportsos-testing-override");
  });
});
