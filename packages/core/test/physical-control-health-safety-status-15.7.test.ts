import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.7 physical control health / safety status", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlHealth.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
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

  it("defines safe, restricted, and emergency locked states", () => {
    expect(service).toContain('"SAFE"');
    expect(service).toContain('"RESTRICTED"');
    expect(service).toContain('"EMERGENCY_LOCKED"');
  });

  it("derives health from authoritative policy and emergency lock services", () => {
    expect(service).toContain("getEmergencyPhysicalControlLock");
    expect(service).toContain("listScoreboardPhysicalControlPolicies");
  });

  it("exposes an authorized health endpoint", () => {
    expect(route).toContain("/scoreboard-control-health");
    expect(route).toContain('"CONTROL_POLICY_READ"');
  });

  it("surfaces health in the operator UI", () => {
    expect(panel).toContain("Physical Control Safety Status");
    expect(panel).toContain("Locked Scopes");
    expect(panel).toContain("Emergency Lock");
    expect(panel).toContain("Global Input");
  });

  it("does not use localStorage as safety authority", () => {
    expect(service).not.toContain("localStorage");
    expect(service).not.toContain("window.");
  });
});
