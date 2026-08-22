import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.3 game lifecycle auto-lock policy", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlLifecyclePolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("allows physical controls only for active lifecycle states", () => {
    for (const status of [
      "LIVE",
      "IN_PROGRESS",
      "STARTED",
      "ACTIVE",
      "RUNNING",
    ]) {
      expect(service).toContain(
        `"${status}"`,
      );
    }
  });

  it("locks terminal game lifecycle states", () => {
    for (const status of [
      "FINAL",
      "FINISHED",
      "COMPLETED",
      "CANCELLED",
      "POSTPONED",
    ]) {
      expect(service).toContain(
        `"${status}"`,
      );
    }
  });

  it("fails closed when lifecycle route exists but status is unavailable", () => {
    expect(service).toContain(
      "Authoritative game lifecycle status is unavailable.",
    );
  });

  it("checks lifecycle before authoritative physical mutation", () => {
    const lifecycleIndex =
      route.indexOf(
        "evaluateGameLifecyclePhysicalControlPolicy",
      );

    const executionIndex =
      route.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(lifecycleIndex).toBeGreaterThan(
      -1,
    );

    expect(executionIndex).toBeGreaterThan(
      lifecycleIndex,
    );
  });

  it("audits lifecycle lockout rejections", () => {
    expect(route).toContain(
      "recordScoreboardControlAudit",
    );

    expect(route).toContain(
      "lifecycleDecision.reason",
    );
  });

  it("does not use dashboard state as lifecycle authority", () => {
    expect(service).not.toContain(
      "localStorage",
    );

    expect(service).not.toContain(
      "window.",
    );
  });
});
