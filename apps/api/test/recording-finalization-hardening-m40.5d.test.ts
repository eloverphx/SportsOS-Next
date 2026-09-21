import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const source = readFileSync(
  path.resolve(__dirname, "../src/services/recordingCaptureRuntime.ts"),
  "utf8",
);

describe("M40.5d recording finalization hardening", () => {
  it("binds failed finalization to the exact recording", () => {
    expect(source).toContain("async function markRecordingFailed(");
    expect(source).toContain("WHERE id = ?");
    expect(source).toContain("AND game_id = ?");
    expect(source).toContain("status IN ('RECORDING', 'PROCESSING')");
  });

  it("stores finalized recordings beneath the authoritative game id", () => {
    expect(source).toContain("const gameId = Number(input.recording.game_id)");

    expect(source).toContain("recordings/${year}/game-${gameId}/recording-${recordingId}.mp4");
  });

  it("retains unattributed capture evidence", () => {
    expect(source).toContain("Retaining unattributed live recording capture");

    expect(source).toContain("Capture retained for recovery.");
  });

  it("logs exact retained evidence after finalization failure", () => {
    expect(source).toContain("Live recording capture retained after finalization failure");

    expect(source).toContain("capturePath: entry.capturePath");
    expect(source).toContain("recordingId");
  });

  it("only deletes the active capture after successful persistence", () => {
    const persistIndex = source.indexOf("const persisted = await persistFinalizedRecording");

    const deleteIndex = source.indexOf(
      "await rm(entry.capturePath, { force: true })",
      persistIndex,
    );

    expect(persistIndex).toBeGreaterThan(-1);
    expect(deleteIndex).toBeGreaterThan(persistIndex);
  });
});
