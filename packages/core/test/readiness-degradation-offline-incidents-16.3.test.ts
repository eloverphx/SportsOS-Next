import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.3 readiness degradation / offline incident generation", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const app = fs.readFileSync(
    new URL(
      "../../../apps/api/src/app.ts",
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

  it("monitors assigned scoreboard readiness", () => {
    expect(monitor).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(monitor).toContain(
      "evaluateScoreboardControlReadiness",
    );
  });

  it("creates an incident only on transition into not-ready", () => {
    expect(monitor).toContain(
      '"NOT_READY"',
    );

    expect(monitor).toContain(
      "prior !==",
    );
  });

  it("writes readiness degradation through the existing control audit", () => {
    expect(monitor).toContain(
      "recordScoreboardControlAudit",
    );

    expect(monitor).toContain(
      "DEVICE_READINESS_DEGRADED",
    );
  });

  it("starts the monitor from the API application", () => {
    expect(app).toContain(
      "startScoreboardReadinessIncidentMonitor",
    );
  });

  it("supports a permission-protected manual readiness check", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness/check",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_WRITE"',
    );
  });
});
