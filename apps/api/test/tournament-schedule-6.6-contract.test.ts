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
    expect(previewRoute).toContain("hardConflict: evaluation.hardConflict");
    expect(previewRoute).toContain("conflicts: evaluation.conflicts");

    expect(previewRoute).not.toContain("updateGame(");
    expect(previewRoute).not.toContain("createGame(");
    expect(previewRoute).not.toContain('method: "PUT"');
  });

  it("delegates update enforcement and preview to one schedule service", () => {
    expect(routes).toContain('from "./schedule-enforcement.js"');
    expect(routes).toContain(
      "evaluateGameInputSchedule(existing.id, parsed.data)",
    );
    expect(routes).toContain("evaluateSchedulePreview(game, {");
    expect(routes).toContain("scheduleEvaluation.hardConflict");
    expect(routes).toContain('code: "SCHEDULE_CONFLICT"');
  });

  it("uses the same pure conflict engine for preview and update evaluation", () => {
    expect(enforcement).toContain("detectServerScheduleConflicts");
    expect(enforcement).toContain("hasHardScheduleConflicts");
    expect(enforcement).toContain("const conflicts = detectServerScheduleConflicts");
    expect(enforcement).toContain(
      "hardConflict: hasHardScheduleConflicts(conflicts)",
    );
  });

  it("rebuilds preview proposals from the authoritative stored game", () => {
    const previewFunctionStart = enforcement.indexOf(
      "export async function evaluateSchedulePreview",
    );

    expect(previewFunctionStart).toBeGreaterThanOrEqual(0);

    const previewFunction = enforcement.slice(previewFunctionStart);

    expect(previewFunction).toContain("id: game.id");
    expect(previewFunction).toContain("homeTeamId: game.homeTeamId");
    expect(previewFunction).toContain("awayTeamId: game.awayTeamId");
    expect(previewFunction).toContain("homeTeamName: game.homeTeamName");
    expect(previewFunction).toContain("awayTeamName: game.awayTeamName");
    expect(previewFunction).toContain("status: game.status");
    expect(previewFunction).toContain(
      "regulationPeriods: game.regulationPeriods",
    );
    expect(previewFunction).toContain(
      "regulationPeriodLengthMs: game.regulationPeriodLengthMs",
    );
    expect(previewFunction).toContain(
      "intermissionLengthMs: game.intermissionLengthMs",
    );
    expect(previewFunction).toContain(
      "overtimeEnabled: game.overtimeEnabled",
    );
    expect(previewFunction).toContain(
      "overtimeLengthMs: game.overtimeLengthMs",
    );

    expect(previewFunction).toContain(
      "scheduledStart: proposed.scheduledStart",
    );
    expect(previewFunction).toContain("venue: proposed.venue");
  });

  it("keeps the server conflict engine behind one reusable evaluation boundary", () => {
    expect(enforcement).toContain(
      "async function evaluate(",
    );
    expect(enforcement).toContain(
      "const existingGames = await listGames({ organizationId })",
    );
    expect(enforcement).toContain(
      "return evaluate(input.organizationId",
    );
    expect(enforcement).toContain(
      "return evaluate(game.organizationId",
    );
  });
});
