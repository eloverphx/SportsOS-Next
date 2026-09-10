import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const goLiveRoutesFile = path.resolve(__dirname, "../src/routes/goLiveSessions.ts");
const recordingRuntimeFile = path.resolve(__dirname, "../src/services/recordingCaptureRuntime.ts");

import {
  buildRecordingCaptureArgs,
  buildRecordingRemuxArgs,
  buildRecordingTranscodeArgs,
} from "../src/services/recordingCaptureFfmpeg.js";

describe("M37.8 live recording capture foundation", () => {
  it("records the source independently from the live publish process", () => {
    expect(buildRecordingCaptureArgs("rtsp://camera/live", "/data/game.capture.mkv")).toEqual([
      "-hide_banner",
      "-nostdin",
      "-loglevel",
      "warning",
      "-i",
      "rtsp://camera/live",
      "-map",
      "0:v?",
      "-map",
      "0:a?",
      "-c",
      "copy",
      "-f",
      "matroska",
      "/data/game.capture.mkv",
    ]);
  });

  it("first attempts a stream-copy faststart MP4 finalization", () => {
    expect(buildRecordingRemuxArgs("/data/source.mkv", "/data/source.mp4")).toEqual([
      "-hide_banner",
      "-nostdin",
      "-loglevel",
      "error",
      "-y",
      "-i",
      "/data/source.mkv",
      "-map",
      "0:v:0?",
      "-map",
      "0:a:0?",
      "-c",
      "copy",
      "-movflags",
      "+faststart",
      "/data/source.mp4",
    ]);
  });

  it("has an H264/AAC fallback for MP4 compatibility", () => {
    const args = buildRecordingTranscodeArgs("/data/source.mkv", "/data/source.mp4");
    expect(args).toContain("libx264");
    expect(args).toContain("aac");
    expect(args).toContain("+faststart");
  });

  it("starts capture after LIVE persistence and finalizes after COMPLETE persistence", () => {
    const route = readFileSync(goLiveRoutesFile, "utf8");

    const livePersist = route.indexOf(
      "const session = markGoLiveLive(gameId);\n    await persistDurableSession(request, gameId, session);",
    );
    const captureStart = route.indexOf("await startRecordingCapture(gameId);");
    const completePersist = route.indexOf(
      "const session = completeGoLiveSession(gameId);\n    await persistDurableSession(request, gameId, session);",
    );
    const finalize = route.indexOf("await stopAndFinalizeRecordingCapture(gameId);");

    expect(livePersist).toBeGreaterThan(-1);
    expect(captureStart).toBeGreaterThan(livePersist);
    expect(completePersist).toBeGreaterThan(-1);
    expect(finalize).toBeGreaterThan(completePersist);
  });

  it("does not publish an emergency-stop capture", () => {
    const route = readFileSync(goLiveRoutesFile, "utf8");
    expect(route).toMatch(
      /emergency-stop[\s\S]*?stopEncoderRuntime\(gameId\);[\s\S]*?stopRecordingCaptureWithoutFinalize\(gameId\);[\s\S]*?markGoLiveEmergencyStopped/,
    );
  });

  it("creates and atomically links a durable VIDEO asset", () => {
    const source = readFileSync(recordingRuntimeFile, "utf8");

    expect(source).toContain("'VIDEO', 'ORGANIZATION'");
    expect(source).toContain("checksum_sha256");
    expect(source).toContain("duration_ms");
    expect(source).toContain("FOR UPDATE");
    expect(source).toContain("SET media_asset_id = ?");
    expect(source).toContain("status = 'READY'");
    expect(source).toContain("minio.putObject");
    expect(source).toContain("minio.removeObject");
    expect(source).toContain("shell: false");
  });
});
