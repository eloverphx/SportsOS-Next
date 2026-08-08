import { describe, expect, it } from "vitest";
import fs from "node:fs";

const source = fs.readFileSync(
  new URL("../../dashboard/app/games/[id]/control/page.tsx", import.meta.url),
  "utf8",
);

describe("scorekeeper console vertical-slice contract", () => {
  it("starts games through the authoritative lifecycle endpoint", () => {
    expect(source).toContain("`/games/${game.id}/lifecycle`");
    expect(source).toContain('command: "startGame"');
    expect(source).toContain("commandId: crypto.randomUUID()");
  });

  it("finishes games through the authoritative lifecycle endpoint", () => {
    expect(source).toContain('command: "finishGame"');
    expect(source).toContain("FINISH GAME");
    expect(source).toContain("Finish game as FINAL?");
  });

  it("requires a paused live game before normal finish", () => {
    expect(source).toContain("const canFinishGame =");
    expect(source).toContain('game.status === "LIVE"');
    expect(source).toContain("!game.clockRunning");
    expect(source).toContain("!game.intermissionRunning");
  });

  it("renders a postgame final score and recap", () => {
    expect(source).toContain("Postgame summary");
    expect(source).toContain("Scoring recap");
    expect(source).toContain("Penalty recap");
    expect(source).toContain("Non-voided game events");
  });

  it("uses only non-voided events for postgame counts", () => {
    expect(source).toContain("const activeEvents = events.filter((event) => !event.voidedAt)");
    expect(source).toContain('activeEvents.filter((event) => event.type === "GOAL")');
    expect(source).toContain('activeEvents.filter((event) => event.type === "PENALTY")');
  });

  it("links postgame operators to scoreboard overlay and diagnostics", () => {
    expect(source).toContain("Public scoreboard");
    expect(source).toContain("Broadcast overlay");
    expect(source).toContain("/system/game-engine/games/${game.id}/diagnostics");
    expect(source).toContain("Engine diagnostics");
  });

  it("preserves pregame readiness and roster-aware workflows", () => {
    expect(source).toContain("Game-day readiness");
    expect(source).toContain("assist1PlayerId: assist1Id || null");
    expect(source).toContain("playerId: penaltyPlayerId || null");
    expect(source).toContain("Penalty clocks");
  });
});
