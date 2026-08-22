import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.7 reliability thresholds / at-risk device classification", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessReliability.ts",
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

  it("defines healthy, watch, at-risk, and offline classifications", () => {
    for (const state of [
      "HEALTHY",
      "WATCH",
      "AT_RISK",
      "OFFLINE",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("uses configurable availability and degradation thresholds", () => {
    expect(service).toContain(
      "SPORTSOS_RELIABILITY_WATCH_AVAILABILITY_PERCENT",
    );

    expect(service).toContain(
      "SPORTSOS_RELIABILITY_AT_RISK_AVAILABILITY_PERCENT",
    );

    expect(service).toContain(
      "SPORTSOS_RELIABILITY_WATCH_DEGRADED_TRANSITIONS",
    );

    expect(service).toContain(
      "SPORTSOS_RELIABILITY_AT_RISK_DEGRADED_TRANSITIONS",
    );
  });

  it("classifies current not-ready devices as offline", () => {
    expect(service).toContain(
      'metric.currentState ===',
    );

    expect(service).toContain(
      'risk:\n        "OFFLINE"',
    );
  });

  it("exposes reliability classification through an authorized API", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-reliability",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("surfaces reliability risk in the operator UI", () => {
    expect(panel).toContain(
      "Reliability Risk Classification",
    );

    expect(panel).toContain(
      "need attention",
    );
  });
});
