import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.9 lifecycle readiness gate enforcement", () => {
  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/modules/games/routes.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("binds readiness enforcement to the real lifecycle route", () => {
    expect(route).toContain(
      'app.post("/games/:id/lifecycle"',
    );
    expect(route).toContain(
      'parsed.data.command === "startGame"',
    );
  });

  it("does not globally gate every startClock action", () => {
    expect(route).toContain(
      "PREGAME_SCOREBOARD_READINESS_GATE_16_9",
    );
    expect(route).toContain(
      "explicit startGame lifecycle command",
    );
  });

  it("resolves the assigned scoreboard and evaluates readiness", () => {
    expect(route).toContain(
      "/scoreboard-devices/assignments",
    );
    expect(route).toContain(
      "evaluatePregameReadinessGate",
    );
  });

  it("returns a conflict when the pregame gate blocks start", () => {
    expect(route).toContain(
      "PREGAME_SCOREBOARD_READINESS_BLOCKED",
    );
    expect(route).toContain(
      "reply.code(409)",
    );
  });
});
