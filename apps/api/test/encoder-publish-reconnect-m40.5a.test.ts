import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const encoder = readFileSync(path.resolve(__dirname, "../src/services/encoderRuntime.ts"), "utf8");

const captureRuntime = readFileSync(
  path.resolve(__dirname, "../src/services/recordingCaptureRuntime.ts"),
  "utf8",
);

const coordinator = readFileSync(
  path.resolve(__dirname, "../src/services/broadcastSessionCoordinator.ts"),
  "utf8",
);

describe("M40.5 publish reconnect isolation", () => {
  it("retries an unexpected encoder failure with bounded backoff", () => {
    expect(encoder).toContain("scheduleEncoderRestart");
    expect(encoder).toContain("maxRecoveryAttempts()");
    expect(encoder).toContain("recoveryBackoffMs(nextAttempt)");
    expect(encoder).toContain('state: "SCHEDULED"');
    expect(encoder).toContain('state: "EXHAUSTED"');
    expect(encoder).toContain("recoveryAttempt: true");
  });

  it("schedules reconnect at most once for an FFmpeg failure", () => {
    expect(encoder).toContain("let recoveryScheduled = false");
    expect(encoder).toContain("const scheduleRecoveryOnce");
    expect(encoder).toContain("entry.stopRequested || recoveryScheduled");
    expect(encoder).toContain("recoveryScheduled = true");

    const errorHandler = encoder.slice(
      encoder.indexOf('child.once("error"'),
      encoder.indexOf('child.once("exit"'),
    );

    expect(errorHandler).toContain("scheduleRecoveryOnce()");
  });

  it("explicit Stop suppresses any pending encoder reconnect", () => {
    const start = encoder.indexOf("export async function stopEncoderRuntime");
    const stopFunction = encoder.slice(start);

    expect(start).toBeGreaterThan(-1);
    expect(stopFunction).toContain("suppressEncoderRecovery(gameId)");
    expect(stopFunction.indexOf("suppressEncoderRecovery(gameId)")).toBeLessThan(
      stopFunction.indexOf("const entry = runtimes.get(gameId)"),
    );
  });

  it("a later deliberate Start resets suppressed recovery", () => {
    const start = encoder.indexOf("export async function startEncoderRuntime");
    const stop = encoder.indexOf("export function suppressEncoderRecovery", start);
    const startFunction = encoder.slice(start, stop);

    expect(startFunction).toContain("if (!input.recoveryAttempt)");
    expect(startFunction).toContain("resetEncoderRecovery(input.gameId)");
  });

  it("publish reconnect remains independent from recording capture", () => {
    expect(encoder).not.toContain("stopRecordingCapture");
    expect(encoder).not.toContain("stopAndFinalizeRecordingCapture");
    expect(encoder).not.toContain("recordingCaptureSupervisor");

    expect(captureRuntime).toContain("recordingCaptureSupervisor");
  });

  it("normal coordinated Stop still finalizes recording after stopping publish", () => {
    const start = coordinator.indexOf("export async function stopCoordinatedBroadcast");
    const stopFunction = coordinator.slice(start);

    const encoderStop = stopFunction.indexOf("await stopEncoderRuntime(gameId)");
    const recordingStop = stopFunction.indexOf("await stopAndFinalizeRecordingCapture(gameId)");

    expect(encoderStop).toBeGreaterThan(-1);
    expect(recordingStop).toBeGreaterThan(encoderStop);
  });

  it("does not persist encoder restart state across process restart", () => {
    expect(encoder).toContain("const recovery = new Map<string, EncoderRecoverySnapshot>()");
    expect(encoder).not.toContain("writeFileSync");
    expect(encoder).not.toContain("readFileSync");
  });
});
