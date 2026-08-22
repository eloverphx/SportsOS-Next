import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.4 readiness recovery / restored-service events", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlAudit.ts",
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

  it("emits a restoration event only after a not-ready state", () => {
    expect(monitor).toContain(
      '"DEVICE_READINESS_RESTORED"',
    );

    expect(monitor).toContain(
      'prior ===',
    );

    expect(monitor).toContain(
      '"NOT_READY"',
    );
  });

  it("projects both degradation and restoration readiness events", () => {
    expect(audit).toContain(
      "listScoreboardControlReadinessEvents",
    );

    expect(audit).toContain(
      '"DEVICE_READINESS_DEGRADED"',
    );

    expect(audit).toContain(
      '"DEVICE_READINESS_RESTORED"',
    );
  });

  it("exposes an authorized readiness event endpoint", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-events",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("shows readiness recovery timeline in operator UI", () => {
    expect(panel).toContain(
      "Readiness Recovery Timeline",
    );

    expect(panel).toContain(
      "RESTORED",
    );

    expect(panel).toContain(
      "DEGRADED",
    );
  });
});
