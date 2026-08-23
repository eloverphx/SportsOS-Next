import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.4 encoder session model / start-stop control foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderSession.ts",
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

  it("defines encoder lifecycle states", () => {
    for (const state of [
      "STOPPED",
      "STARTING",
      "LIVE",
      "STOPPING",
      "ERROR",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("persists encoder sessions separately from stream destinations", () => {
    expect(service).toContain(
      "encoder-sessions.json",
    );
  });

  it("blocks start until destination is ready", () => {
    expect(route).toContain(
      'destination.status !==\n          "READY"',
    );

    expect(route).toContain(
      "Stream destination must be READY before encoder start.",
    );
  });

  it("provides start and stop control routes", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/start"',
    );

    expect(route).toContain(
      '"/encoder-sessions/:gameId/stop"',
    );
  });

  it("provides operator encoder controls", () => {
    expect(panel).toContain(
      "Encoder Session",
    );

    expect(panel).toContain(
      "Arm Encoder Start",
    );

    expect(panel).toContain(
      "Stop Encoder Session",
    );
  });

  it("does not launch media processes in this milestone", () => {
    expect(service).not.toContain(
      "child_process",
    );

    expect(route).not.toContain(
      "ffmpeg",
    );
  });
});
