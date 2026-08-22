import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.1 device control heartbeat / readiness gate", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlReadiness.ts",
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

  const policyRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("uses scoreboard device heartbeat state as readiness authority", () => {
    expect(service).toContain(
      "findScoreboardDeviceById",
    );

    expect(service).toContain(
      "lastHeartbeatAt",
    );
  });

  it("defaults heartbeat readiness to 30 seconds", () => {
    expect(service).toContain(
      '"30000"',
    );

    expect(service).toContain(
      "SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS",
    );
  });

  it("rejects stale or missing heartbeat before physical mutation", () => {
    const readinessIndex =
      inputRoute.indexOf(
        "evaluateScoreboardControlReadiness",
      );

    const executionIndex =
      inputRoute.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(readinessIndex).toBeGreaterThan(
      -1,
    );

    expect(executionIndex).toBeGreaterThan(
      readinessIndex,
    );

    expect(inputRoute).toContain(
      "readinessDecision.ready",
    );
  });

  it("audits readiness rejections", () => {
    expect(inputRoute).toContain(
      "recordScoreboardControlAudit",
    );

    expect(inputRoute).toContain(
      "readinessDecision.reason",
    );
  });

  it("exposes an authorized readiness endpoint", () => {
    expect(policyRoute).toContain(
      "/scoreboard-control-readiness/:deviceId",
    );

    expect(policyRoute).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });
});
