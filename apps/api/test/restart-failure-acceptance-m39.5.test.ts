import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = readFileSync(path.resolve(__dirname, "../src/app.ts"), "utf8");

const runtime = readFileSync(
  path.resolve(__dirname, "../src/services/recordingCaptureRuntime.ts"),
  "utf8",
);

const goLiveRoutes = readFileSync(
  path.resolve(__dirname, "../src/routes/goLiveSessions.ts"),
  "utf8",
);

describe("M39.5 restart and failure acceptance", () => {
  it("recovers interrupted recording media before broadcast supervision begins", () => {
    const recovery = app.indexOf("await recoverRecordingCapturesOnStartup()");
    const supervisor = app.indexOf("startBroadcastCoordinatorSupervisor({");

    expect(recovery).toBeGreaterThan(-1);
    expect(supervisor).toBeGreaterThan(-1);
    expect(recovery).toBeLessThan(supervisor);
  });

  it("treats restart recovery as archival recovery, never live-stream auto-resume", () => {
    const start = runtime.indexOf("export async function recoverRecordingCapturesOnStartup");

    expect(start).toBeGreaterThan(-1);

    const recovery = runtime.slice(start);

    expect(recovery).toContain("finalizeCaptureFile(capturePath)");
    expect(recovery).toContain("persistFinalizedRecording({");

    expect(recovery).not.toContain("startEncoderRuntime");
    expect(recovery).not.toContain("markGoLiveLive");
    expect(recovery).not.toContain("syncDurableGoLiveSession");
  });

  it("requires an exact durable recording and game binding before recovery", () => {
    expect(runtime).toContain(
      "const orphanPattern = /^recording-(\\d+)-game-(\\d+)-(\\d+)\\.capture\\.mkv$/;",
    );

    expect(runtime).toContain("durableRecordingById(recordingId, gameId)");

    expect(runtime).toContain('[\"RECORDING\", \"PROCESSING\"].includes(recording.status)');
  });

  it("preserves failed or unattributable captures for operator investigation", () => {
    const start = runtime.indexOf("export async function recoverRecordingCapturesOnStartup");

    const recovery = runtime.slice(start);

    expect(recovery).toContain("summary.skipped += 1");
    expect(recovery).toContain("summary.failed += 1");

    expect(recovery).toContain('"Unable to recover orphaned live recording capture after startup"');
  });

  it("cleans stale capture files when the durable recording is already finalized", () => {
    const start = runtime.indexOf("export async function recoverRecordingCapturesOnStartup");

    const recovery = runtime.slice(start);

    expect(recovery).toContain(
      'recording.media_asset_id != null || ["READY", "ARCHIVED"].includes(recording.status)',
    );
    expect(recovery).toContain("await rm(capturePath, { force: true }).catch(() => undefined)");
    expect(recovery).toContain(
      "await rm(`${capturePath}.mp4`, { force: true }).catch(() => undefined)",
    );
    expect(recovery).toContain("summary.cleaned += 1");
  });

  it("keeps the live broadcast available when archive capture cannot start", () => {
    const confirmStart = goLiveRoutes.indexOf('app.post("/go-live-sessions/:gameId/confirm-live"');

    const emergencyStop = goLiveRoutes.indexOf(
      'app.post("/go-live-sessions/:gameId/emergency-stop"',
      confirmStart,
    );

    expect(confirmStart).toBeGreaterThan(-1);
    expect(emergencyStop).toBeGreaterThan(confirmStart);

    const confirmLive = goLiveRoutes.slice(confirmStart, emergencyStop);

    expect(confirmLive).toContain("try {");
    expect(confirmLive).toContain("await startRecordingCapture(gameId)");
    expect(confirmLive).toContain(
      'request.log.error({ error, gameId }, "Live recording capture failed to start")',
    );
  });
});
