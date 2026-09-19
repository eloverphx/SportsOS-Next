import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const runtime = readFileSync(
  new URL("../src/services/recordingCaptureRuntime.ts", import.meta.url),
  "utf8",
);

const supervisor = readFileSync(
  new URL("../src/workers/recordingCaptureSupervisor.ts", import.meta.url),
  "utf8",
);

const client = readFileSync(
  new URL("../src/services/recordingCaptureSupervisorClient.ts", import.meta.url),
  "utf8",
);

const compose = readFileSync(new URL("../../../docker-compose.yml", import.meta.url), "utf8");

describe("M40.3a persistent recording capture supervisor", () => {
  it("moves long-running FFmpeg capture ownership out of the API runtime", () => {
    expect(runtime).not.toContain("new Map<string, CaptureEntry>()");
    expect(runtime).not.toContain("buildRecordingCaptureArgs");
    expect(runtime).not.toContain("spawn(ffmpegPath(), buildRecordingCaptureArgs");
    expect(runtime).toContain("startSupervisorRecordingCapture");
    expect(runtime).toContain("stopSupervisorRecordingCapture");

    expect(supervisor).toContain('from "node:child_process"');
    expect(supervisor).toContain("buildRecordingCaptureArgs");
    expect(supervisor).toContain("const captures = new Map<string, CaptureEntry>()");
    expect(supervisor).toContain("buildRecordingCaptureArgs(input.sourceUrl, capturePath)");
  });

  it("does not let the supervisor reconstruct broadcasts from durable state", () => {
    expect(supervisor).not.toContain("infrastructure/database");
    expect(supervisor).not.toContain("FROM recordings");
    expect(supervisor).not.toContain("SELECT");
    expect(supervisor).not.toContain("recoverRecordingCapturesOnStartup");
  });

  it("protects active supervisor files from API startup orphan recovery", () => {
    expect(runtime).toContain("listSupervisorRecordingCaptures");
    expect(runtime).toContain("activeCapturePaths");
    expect(runtime).toContain("activeCapturePaths.has(path.resolve(capturePath))");
    expect(runtime).toContain(
      "Skipping orphan recording recovery because capture supervisor status is unavailable",
    );
  });

  it("keeps the supervisor internal and independent from API health", () => {
    expect(compose).toContain("capture-supervisor:");
    expect(compose).toContain("sportsos_capture_supervisor");
    expect(compose).toContain(
      'command: ["node", "apps/api/dist/workers/recordingCaptureSupervisor.js"]',
    );
    expect(compose).toContain("SPORTSOS_CAPTURE_SUPERVISOR_URL: http://capture-supervisor:4015");

    const supervisorBlock = compose.split("  capture-supervisor:")[1]?.split("\n  api:")[0] ?? "";

    expect(supervisorBlock).not.toContain("ports:");
    expect(supervisorBlock).not.toContain("api: { condition:");
  });

  it("supports an internal bearer token without placing it in capture payloads", () => {
    expect(client).toContain("SPORTSOS_CAPTURE_SUPERVISOR_TOKEN");
    expect(client).toContain("headers.authorization");
    expect(supervisor).toContain("SPORTSOS_CAPTURE_SUPERVISOR_TOKEN");
  });
});
