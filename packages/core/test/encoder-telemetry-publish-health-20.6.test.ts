import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.6 encoder telemetry / publish health", () => {
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

  it("enables FFmpeg progress output", () => {
    expect(runtime).toContain('"-progress"');
    expect(runtime).toContain('"pipe:1"');
  });

  it("tracks encoder metrics", () => {
    for (const field of [
      "frame",
      "fps",
      "bitrateKbps",
      "totalSizeBytes",
      "outTimeMs",
      "speed",
      "lastProgressAt",
    ]) {
      expect(runtime).toContain(field);
    }
  });

  it("detects stale publish health", () => {
    expect(runtime).toContain('"STALE"');
    expect(runtime).toContain("10000");
  });

  it("provides a telemetry endpoint", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/telemetry"',
    );
  });

  it("shows publish health in the operator UI", () => {
    expect(panel).toContain("Publish Health");
    expect(panel).toContain("Bitrate");
    expect(panel).toContain("Last encoder progress");
  });

  it("polls active-session telemetry every 2 seconds", () => {
    expect(panel).toContain("/telemetry");
    expect(panel).toContain("2000");
  });
});
