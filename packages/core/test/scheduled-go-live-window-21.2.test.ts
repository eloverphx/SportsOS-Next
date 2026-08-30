import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 21.2 scheduled go-live / start window foundation", () => {
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

  it("persists scheduled start and window bounds", () => {
    expect(service).toContain(
      "scheduledStartAt",
    );
    expect(service).toContain(
      "startWindowEarlyMinutes",
    );
    expect(service).toContain(
      "startWindowLateMinutes",
    );
  });

  it("evaluates start-window state", () => {
    expect(service).toContain(
      "evaluateGoLiveStartWindow",
    );
    expect(service).toContain(
      "withinWindow",
    );
    expect(service).toContain(
      "tooEarly",
    );
    expect(service).toContain(
      "tooLate",
    );
  });

  it("provides schedule and window APIs", () => {
    expect(route).toContain(
      '"/go-live-sessions/:gameId/schedule"',
    );
    expect(route).toContain(
      '"/go-live-sessions/:gameId/start-window"',
    );
  });

  it("blocks scheduled starts outside the window", () => {
    expect(route).toContain(
      "GO_LIVE_START_WINDOW_21_2",
    );
    expect(route).toContain(
      "Go-live start window has not opened yet.",
    );
    expect(route).toContain(
      "Go-live start window has expired.",
    );
  });

  it("provides operator scheduling controls", () => {
    expect(panel).toContain(
      "Scheduled Start",
    );
    expect(panel).toContain(
      "Early Window (minutes)",
    );
    expect(panel).toContain(
      "Late Window (minutes)",
    );
    expect(panel).toContain(
      "Save Go-Live Schedule",
    );
  });
});
