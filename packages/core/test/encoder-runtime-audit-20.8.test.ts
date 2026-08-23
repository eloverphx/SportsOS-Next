import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.8 encoder runtime audit / failure history", () => {
  const audit =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntimeAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/encoderSessions.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists bounded encoder audit history", () => {
    expect(audit).toContain(
      "encoder-runtime-audit.json",
    );

    expect(audit).toContain(
      "1000",
    );
  });

  it("records runtime and recovery events", () => {
    for (const event of [
      "RUNTIME_STARTED",
      "RUNTIME_LIVE",
      "RUNTIME_STOPPED",
      "RUNTIME_ERROR",
      "RESTART_SCHEDULED",
      "RESTARTING",
      "RESTART_EXHAUSTED",
    ]) {
      expect(runtime).toContain(
        `"${event}"`,
      );
    }
  });

  it("records operator start and stop requests", () => {
    expect(route).toContain(
      '"START_REQUESTED"',
    );

    expect(route).toContain(
      '"STOP_REQUESTED"',
    );
  });

  it("provides an audit endpoint", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/audit"',
    );

    expect(route).toContain(
      "listEncoderAuditEvents",
    );
  });

  it("shows encoder history in the operator UI", () => {
    expect(panel).toContain(
      "Encoder Runtime History",
    );

    expect(panel).toContain(
      "/audit?limit=12",
    );
  });
});
