import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.1 physical control enable/lockout policy", () => {
  const policy = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlPolicy.ts",
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

  it("supports game device and game-device policy scopes", () => {
    for (const scope of [
      "GAME",
      "DEVICE",
      "GAME_DEVICE",
    ]) {
      expect(policy).toContain(
        `"${scope}"`,
      );
    }
  });

  it("supports enabled and locked modes", () => {
    expect(policy).toContain(
      '"ENABLED"',
    );

    expect(policy).toContain(
      '"LOCKED"',
    );
  });

  it("persists server-side policy state", () => {
    expect(policy).toContain(
      "scoreboard-control-policy.json",
    );

    expect(policy).toContain(
      "persistStore",
    );
  });

  it("checks policy before authoritative mutation execution", () => {
    const policyIndex =
      route.indexOf(
        "evaluateScoreboardPhysicalControlPolicy",
      );

    const executionIndex =
      route.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(policyIndex).toBeGreaterThan(
      -1,
    );

    expect(executionIndex).toBeGreaterThan(
      policyIndex,
    );
  });

  it("returns a locked response and writes an audit record", () => {
    expect(route).toContain(
      "reply.code(423)",
    );

    expect(route).toContain(
      "recordScoreboardControlAudit",
    );

    expect(route).toContain(
      "Physical scoreboard controls are locked.",
    );
  });

  it("does not reference localStorage or testing override authority", () => {
    expect(policy).not.toContain(
      "localStorage",
    );

    expect(policy).not.toContain(
      "testingOverride",
    );
  });
});
