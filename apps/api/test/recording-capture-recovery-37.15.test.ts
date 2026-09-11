import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const runtime = readFileSync(
  path.resolve(__dirname, "../src/services/recordingCaptureRuntime.ts"),
  "utf8",
);
const app = readFileSync(path.resolve(__dirname, "../src/app.ts"), "utf8");

describe("M37.15 API-restart recording recovery", () => {
  it("names new durable captures with the exact recording id", () => {
    expect(runtime).toContain(
      "`recording-${recordingId}-game-${safeGameId(gameId)}-${Date.now()}.capture.mkv`",
    );
    expect(runtime).toContain('durableRecording.status === "RECORDING"');
    expect(runtime).toContain("durableRecording.media_asset_id == null");
  });

  it("only recovers precisely attributable orphaned capture files", () => {
    expect(runtime).toContain(
      "const orphanPattern = /^recording-(\\d+)-game-(\\d+)-(\\d+)\\.capture\\.mkv$/;",
    );
    expect(runtime).toContain("durableRecordingById(recordingId, gameId)");
    expect(runtime).toContain('["RECORDING", "PROCESSING"].includes(recording.status)');
  });

  it("reuses the existing finalization transaction", () => {
    const start = runtime.indexOf("export async function recoverRecordingCapturesOnStartup");
    const recovery = runtime.slice(start);

    expect(recovery).toContain("finalizeCaptureFile(capturePath)");
    expect(recovery).toContain("probeDurationMs(outputPath)");
    expect(recovery).toContain("sha256File(outputPath)");
    expect(recovery).toContain("persistFinalizedRecording({");
    expect(recovery).not.toContain("INSERT INTO media_assets");
  });

  it("does not auto-resume streaming during capture recovery", () => {
    const start = runtime.indexOf("export async function recoverRecordingCapturesOnStartup");
    const recovery = runtime.slice(start);

    expect(recovery).not.toContain("startEncoderRuntime");
    expect(recovery).not.toContain("markGoLiveLive");
    expect(recovery).not.toContain("syncDurableGoLiveSession");
  });

  it("runs orphan recovery before the broadcast supervisor starts", () => {
    const recovery = app.indexOf("await recoverRecordingCapturesOnStartup()");
    const supervisor = app.indexOf("startBroadcastCoordinatorSupervisor({");

    expect(recovery).toBeGreaterThan(-1);
    expect(supervisor).toBeGreaterThan(recovery);
  });

  it("retains non-finalizable or failed captures for operator evidence", () => {
    expect(runtime).toContain("summary.skipped += 1");
    expect(runtime).toContain("summary.failed += 1");
    expect(runtime).toContain('"Unable to recover orphaned live recording capture after startup"');
  });
});
