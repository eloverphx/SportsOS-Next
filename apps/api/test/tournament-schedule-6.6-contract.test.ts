import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const routes = readFileSync(
  new URL("../src/modules/games/routes.ts", import.meta.url),
  "utf8",
);

const enforcement = readFileSync(
  new URL("../src/modules/games/schedule-enforcement.ts", import.meta.url),
  "utf8",
);

const mutations = readFileSync(
  new URL("../src/modules/games/schedule-mutations.ts", import.meta.url),
  "utf8",
);

describe("Tournament scheduling 6.6 authoritative preview contract", () => {
  it("exposes a non-mutating schedule preview route", () => {
    const previewStart = routes.indexOf(
      'app.post("/games/:id/schedule-preview"',
    );
    const scoringStart = routes.indexOf(
      'app.post("/games/:id/scoring"',
      previewStart,
    );

    expect(previewStart).toBeGreaterThanOrEqual(0);
    expect(scoringStart).toBeGreaterThan(previewStart);

    const previewRoute = routes.slice(previewStart, scoringStart);

    expect(previewRoute).toContain("permission: PERMISSIONS.GAME_MANAGE");
    expect(previewRoute).toContain("GAME_NOT_SCHEDULED");
    expect(previewRoute).toContain("evaluateSchedulePreview");
    expect(previewRoute).not.toContain("updateGame(");
    expect(previewRoute).not.toContain("createGame(");
  });

  it("delegates authoritative update enforcement through the schedule mutation service", () => {
    expect(routes).toContain('from "./schedule-mutations.js"');
    expect(routes).toContain("updateGameWithScheduleTransaction(");
    expect(mutations).toContain("evaluateInsideTransaction");
    expect(mutations).toContain(
      "evaluateGameInputScheduleAgainstExisting(",
    );
  });

  it("uses the same pure conflict engine for preview and update evaluation", () => {
    expect(enforcement).toContain("detectServerScheduleConflicts");
    expect(enforcement).toContain("hasHardScheduleConflicts");
  });

  it("rebuilds preview proposals from the authoritative stored game", () => {
    const previewFunctionStart = enforcement.indexOf(
      "export async function evaluateSchedulePreview",
    );
    const previewFunction = enforcement.slice(previewFunctionStart);

    expect(previewFunction).toContain("id: game.id");
    expect(previewFunction).toContain("homeTeamId: game.homeTeamId");
    expect(previewFunction).toContain("awayTeamId: game.awayTeamId");
    expect(previewFunction).toContain("status: game.status");
    expect(previewFunction).toContain(
      "scheduledStart: proposed.scheduledStart",
    );
    expect(previewFunction).toContain("venue: proposed.venue");
  });

  it("keeps the conflict engine reusable across preview and transactional writes", () => {
    expect(enforcement).toContain("async function evaluate(");
    expect(enforcement).toContain(
      "export function evaluateGameInputScheduleAgainstExisting",
    );
  });
});
