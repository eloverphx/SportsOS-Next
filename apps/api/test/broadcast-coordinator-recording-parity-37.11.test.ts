import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const coordinatorFile = path.resolve(__dirname, "../src/services/broadcastSessionCoordinator.ts");

describe("M37.11 broadcast coordinator durable recording parity", () => {
  const source = readFileSync(coordinatorFile, "utf8");

  it("uses the existing durable go-live bridge instead of a parallel persistence path", () => {
    expect(source).toContain(
      'import { syncDurableGoLiveSession } from "./durableGoLiveBridge.js";',
    );
    expect(source).not.toContain("INSERT INTO recordings");
    expect(source).not.toContain("INSERT INTO stream_sessions");
  });

  it("persists STARTING before launching the encoder runtime", () => {
    const syncIndex = source.indexOf("await syncDurableGoLiveSession({");
    const encoderIndex = source.indexOf("await startEncoderRuntime({");

    expect(syncIndex).toBeGreaterThan(-1);
    expect(encoderIndex).toBeGreaterThan(syncIndex);
    expect(source.slice(syncIndex, encoderIndex)).toContain("status: starting.status");
  });

  it("persists STOPPING and COMPLETE around encoder shutdown", () => {
    const stopFunction = source.slice(
      source.indexOf("export async function stopCoordinatedBroadcast"),
    );
    const stoppingSync = stopFunction.indexOf("status: stopping.status");
    const encoderStop = stopFunction.indexOf("await stopEncoderRuntime(gameId)");
    const completeSync = stopFunction.indexOf("status: completed.status");

    expect(stoppingSync).toBeGreaterThan(-1);
    expect(encoderStop).toBeGreaterThan(stoppingSync);
    expect(completeSync).toBeGreaterThan(encoderStop);
  });

  it("finalizes the existing M37.8 capture only after durable COMPLETE persistence", () => {
    const stopFunction = source.slice(
      source.indexOf("export async function stopCoordinatedBroadcast"),
    );
    const completeSync = stopFunction.indexOf("status: completed.status");
    const finalization = stopFunction.indexOf("await stopAndFinalizeRecordingCapture(gameId)");

    expect(finalization).toBeGreaterThan(completeSync);
    expect(source).toContain(
      'import { stopAndFinalizeRecordingCapture } from "./recordingCaptureRuntime.js";',
    );
  });

  it("does not invent a second recording capture runtime", () => {
    expect(source).not.toContain("startRecordingCapture(");
    expect(source).not.toContain("spawn(");
    expect(source).not.toContain("ffmpeg");
  });
});
