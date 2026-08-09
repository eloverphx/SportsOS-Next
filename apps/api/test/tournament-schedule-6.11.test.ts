import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  MAX_SCHEDULE_OVERRIDE_REASON_LENGTH,
  parseScheduleOverride,
} from "../src/modules/games/schedule-enforcement.js";

const routes = readFileSync(
  new URL("../src/modules/games/routes.ts", import.meta.url),
  "utf8",
);

const editor = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleEditor.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.11 hardening", () => {
  it("parses explicit schedule overrides without trusting arbitrary body values", () => {
    expect(parseScheduleOverride(null)).toEqual({
      override: false,
      reason: null,
      reasonTooLong: false,
    });

    expect(
      parseScheduleOverride({
        scheduleConflictOverride: "true",
        scheduleConflictOverrideReason: " ignored ",
      }),
    ).toEqual({
      override: false,
      reason: "ignored",
      reasonTooLong: false,
    });

    expect(
      parseScheduleOverride({
        scheduleConflictOverride: true,
        scheduleConflictOverrideReason: "  Tournament director approved rink exception  ",
      }),
    ).toEqual({
      override: true,
      reason: "Tournament director approved rink exception",
      reasonTooLong: false,
    });
  });

  it("detects oversized override reasons", () => {
    const parsed = parseScheduleOverride({
      scheduleConflictOverride: true,
      scheduleConflictOverrideReason: "x".repeat(
        MAX_SCHEDULE_OVERRIDE_REASON_LENGTH + 1,
      ),
    });

    expect(parsed.override).toBe(true);
    expect(parsed.reasonTooLong).toBe(true);
  });

  it("protects POST /games with the authoritative schedule evaluator", () => {
    const postStart = routes.indexOf('app.post("/games"');
    const putStart = routes.indexOf('app.put("/games/:id"');
    const post = routes.slice(postStart, putStart);

    expect(post).toContain("evaluateNewGameSchedule(parsed.data)");
    expect(post).toContain("game.schedule_create_conflict_blocked");
    expect(post).toContain("game.schedule_create_conflict_overridden");
    expect(post).toContain('code: "SCHEDULE_CONFLICT"');
    expect(post).toContain('code: "SCHEDULE_OVERRIDE_REASON_REQUIRED"');
    expect(post).toContain("reason: scheduleOverride.reason");
  });

  it("requires and audits a reason for PUT hard-conflict overrides", () => {
    const putStart = routes.indexOf('app.put("/games/:id"');
    const previewStart = routes.indexOf(
      'app.post("/games/:id/schedule-preview"',
      putStart,
    );
    const put = routes.slice(putStart, previewStart);

    expect(put).toContain("parseScheduleOverride(request.body)");
    expect(put).toContain(
      "scheduleRelevantFieldsChanged(existing, parsed.data)",
    );
    expect(put).toContain('code: "SCHEDULE_OVERRIDE_REASON_REQUIRED"');
    expect(put).toContain("scheduleConflictOverrideReason: scheduleOverride.reason");
    expect(put).toContain("reason: scheduleOverride.reason");
  });

  it("collects the override reason in Tournament Director", () => {
    expect(editor).toContain("scheduleOverrideReason");
    expect(editor).toContain("Override reason");
    expect(editor).toContain("maxLength={500}");
    expect(editor).toContain(
      "Enter a reason for overriding the hard schedule conflict.",
    );
    expect(editor).toContain("scheduleConflictOverrideReason:");
    expect(editor).toContain("This reason is stored");
  });
});
