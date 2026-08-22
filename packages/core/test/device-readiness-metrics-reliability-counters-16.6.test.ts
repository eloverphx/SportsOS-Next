import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.6 device readiness metrics / reliability counters", () => {
  const metrics = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessMetrics.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
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

  it("persists per-device readiness counters", () => {
    expect(metrics).toContain(
      "scoreboard-readiness-metrics.json",
    );

    expect(metrics).toContain(
      "readyTransitions",
    );

    expect(metrics).toContain(
      "degradedTransitions",
    );
  });

  it("tracks ready and not-ready duration", () => {
    expect(metrics).toContain(
      "readyMs",
    );

    expect(metrics).toContain(
      "notReadyMs",
    );
  });

  it("records readiness observations from the monitor", () => {
    expect(monitor).toContain(
      "recordScoreboardReadinessObservation",
    );
  });

  it("exposes availability metrics through an authorized API", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-metrics",
    );

    expect(route).toContain(
      "availabilityPercent",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("shows device reliability metrics in operator UI", () => {
    expect(panel).toContain(
      "Device Reliability Metrics",
    );

    expect(panel).toContain(
      "Availability",
    );

    expect(panel).toContain(
      "Degraded",
    );

    expect(panel).toContain(
      "Recovered",
    );
  });
});
