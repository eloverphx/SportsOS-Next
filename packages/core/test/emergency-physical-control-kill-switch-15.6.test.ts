import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.6 emergency physical control kill switch", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardEmergencyControlLock.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const policyRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const inputRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("persists emergency lock state", () => {
    expect(service).toContain(
      "scoreboard-emergency-control-lock.json",
    );
    expect(service).toContain("active");
    expect(service).toContain("actorUserId");
  });

  it("requires policy permissions to operate emergency lock", () => {
    expect(policyRoute).toContain(
      "/scoreboard-control-emergency-lock",
    );
    expect(policyRoute).toContain(
      '"CONTROL_POLICY_WRITE"',
    );
    expect(policyRoute).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("requires a reason when activating the emergency lock", () => {
    expect(policyRoute).toContain(
      "A reason is required to activate the emergency lock.",
    );
  });

  it("rejects physical mutation before execution while emergency lock is active", () => {
    const lockIndex =
      inputRoute.indexOf(
        "emergencyPhysicalControlLock",
      );
    const executionIndex =
      inputRoute.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(lockIndex).toBeGreaterThan(-1);
    expect(executionIndex).toBeGreaterThan(lockIndex);
    expect(inputRoute).toContain("reply.code(423)");
  });

  it("exposes emergency lock controls in operator UI", () => {
    expect(panel).toContain(
      "Emergency Physical Control Lock",
    );
    expect(panel).toContain(
      "Activate Emergency Lock",
    );
    expect(panel).toContain(
      "Clear Emergency Lock",
    );
  });
});
