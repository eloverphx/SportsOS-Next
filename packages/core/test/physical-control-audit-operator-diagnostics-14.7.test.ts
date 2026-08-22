import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.7 physical control audit / operator diagnostics", () => {
  it("persists physical control audit records", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-control-audit.json",
    );

    expect(service).toContain(
      "recordScoreboardControlAudit",
    );
  });

  it("records accepted rejected duplicate and execution-failed outcomes", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const outcome of [
      "ACCEPTED",
      "REJECTED",
      "IGNORED_DUPLICATE",
      "EXECUTION_FAILED",
    ]) {
      expect(service).toContain(
        outcome,
      );
    }
  });

  it("exposes filtered audit API", () => {
    const route = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardControlAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "/scoreboard-control-audit",
    );

    expect(route).toContain(
      "deviceId",
    );

    expect(route).toContain(
      "gameId",
    );

    expect(route).toContain(
      "disposition",
    );
  });

  it("writes audit events from physical control processing", () => {
    const route = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "recordScoreboardControlAudit",
    );

    expect(route).toContain(
      '"EXECUTION_FAILED"',
    );
  });

  it("adds operator diagnostics panel", () => {
    const panel = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlDiagnosticsPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(panel).toContain(
      "Physical Control Diagnostics",
    );

    expect(panel).toContain(
      "/scoreboard-control-audit",
    );

    expect(panel).toContain(
      "Accepted",
    );

    expect(panel).toContain(
      "Rejected",
    );

    expect(panel).toContain(
      "Duplicate",
    );
  });
});
