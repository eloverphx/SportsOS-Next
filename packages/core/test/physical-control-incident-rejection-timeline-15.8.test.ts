import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.8 physical control incident / rejection timeline", () => {
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

  it("derives incidents from rejected or errored control audit records", () => {
    expect(audit).toContain(
      "listScoreboardControlIncidents",
    );
    expect(audit).toContain(
      'record.disposition === "REJECTED"',
    );
    expect(audit).toContain(
      "Boolean(record.error)",
    );
  });

  it("exposes an authorized incident endpoint", () => {
    expect(route).toContain(
      "/scoreboard-control-incidents",
    );
    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("preserves device, game, input, sequence, error, and timestamp context", () => {
    for (const field of [
      "deviceId",
      "gameId",
      "inputId",
      "inputType",
      "sequence",
      "error",
      "createdAt",
    ]) {
      expect(audit).toContain(field);
    }
  });

  it("renders an operator incident timeline", () => {
    expect(panel).toContain(
      "Physical Control Incident Timeline",
    );
    expect(panel).toContain(
      "No physical-control incidents recorded.",
    );
    expect(panel).toContain(
      "incident.deviceId",
    );
    expect(panel).toContain(
      "incident.error",
    );
  });

  it("keeps the server audit as timeline authority", () => {
    expect(audit).not.toContain("localStorage");
    expect(audit).not.toContain("window.");
  });
});
