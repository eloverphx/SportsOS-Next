import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const runtime = readFileSync(
  path.resolve(__dirname, "../src/services/recordingCaptureRuntime.ts"),
  "utf8",
);
const supervisor = readFileSync(
  path.resolve(__dirname, "../src/workers/recordingCaptureSupervisor.ts"),
  "utf8",
);
const routes = readFileSync(path.resolve(__dirname, "../src/routes/goLiveSessions.ts"), "utf8");

describe("M37.18 durable recording binding", () => {
  it("fails capture start when no exact durable RECORDING row is available", () => {
    expect(runtime).toContain("!durableRecording");
    expect(runtime).toContain("durableRecording.media_asset_id != null");
    expect(runtime).toContain('durableRecording.status !== "RECORDING"');
    expect(runtime).toContain(
      "Live recording capture requires an unfinalized durable RECORDING row for this game.",
    );
  });

  it("never creates the legacy unbound capture filename", () => {
    expect(supervisor).not.toContain(
      "`game-${safeGameId(input.gameId)}-${Date.now()}.capture.mkv`",
    );
    expect(supervisor).toContain(
      "`recording-${input.recordingId}-game-${safeGameId(input.gameId)}-`",
    );
    expect(supervisor).toContain("`${Date.now()}.capture.mkv`");
  });

  it("keeps broadcast availability independent from archive-capture start failure", () => {
    const confirmStart = routes.indexOf('app.post("/go-live-sessions/:gameId/confirm-live"');
    const emergencyStart = routes.indexOf(
      'app.post("/go-live-sessions/:gameId/emergency-stop"',
      confirmStart,
    );
    const confirmLive = routes.slice(confirmStart, emergencyStart);

    expect(confirmLive).toContain("try {");
    expect(confirmLive).toContain("await startRecordingCapture(gameId)");
    expect(confirmLive).toContain(
      'request.log.error({ error, gameId }, "Live recording capture failed to start")',
    );
  });

  it("preserves exact recording-id recovery filenames", () => {
    expect(runtime).toContain(
      "const orphanPattern = /^recording-(\\d+)-game-(\\d+)-(\\d+)\\.capture\\.mkv$/;",
    );
  });
});
