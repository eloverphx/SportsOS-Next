import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 21.1 production go-live session foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/goLiveSession.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/goLiveSessions.ts",
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

  it("defines production go-live lifecycle states", () => {
    for (const state of [
      "IDLE",
      "ARMED",
      "STARTING",
      "LIVE",
      "STOPPING",
      "COMPLETE",
      "ERROR",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("persists go-live sessions separately", () => {
    expect(service).toContain(
      "go-live-sessions.json",
    );
  });

  it("requires streaming readiness before arming and start", () => {
    expect(route).toContain(
      "evaluateStreamingReadiness",
    );

    expect(route).toContain(
      "Streaming readiness preflight must pass before arming go-live.",
    );

    expect(route).toContain(
      "Streaming readiness preflight failed before go-live start.",
    );
  });

  it("requires encoder live plus healthy telemetry before confirmation", () => {
    expect(route).toContain(
      'runtime.session.status !==\n          "LIVE"',
    );

    expect(route).toContain(
      'runtime.telemetry.health !==\n          "HEALTHY"',
    );
  });

  it("provides operator go-live controls", () => {
    expect(panel).toContain(
      "Production Go-Live",
    );

    expect(panel).toContain(
      "Arm Go-Live",
    );

    expect(panel).toContain(
      "Start Go-Live",
    );

    expect(panel).toContain(
      "Confirm Live",
    );

    expect(panel).toContain(
      "Stop Go-Live",
    );
  });
});
