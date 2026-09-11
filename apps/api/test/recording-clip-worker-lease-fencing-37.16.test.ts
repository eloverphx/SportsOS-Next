import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repository = readFileSync(
  path.resolve(__dirname, "../src/modules/recording-clip-jobs/repository.ts"),
  "utf8",
);
const worker = readFileSync(
  path.resolve(__dirname, "../src/services/recordingClipWorker.ts"),
  "utf8",
);

describe("M37.16 clip-worker lease fencing", () => {
  it("passes the claimed attempt generation into completion", () => {
    expect(worker).toContain("attemptCount: job.attemptCount");
  });

  it("requires the same attempt generation for completion", () => {
    expect(repository).toContain("readonly attemptCount: number");
    expect(repository).toContain("Number(row.attempt_count) !== input.attemptCount");
    expect(repository).toContain("AND attempt_count = ?");
    expect(repository).toContain("[outputMediaAssetId, input.jobId, input.attemptCount]");
  });

  it("requires the same attempt generation for failure/requeue", () => {
    const start = repository.indexOf("export async function markRecordingClipJobAttemptFailed");
    const end = repository.indexOf("interface CompletionRow", start);
    const failureSource = repository.slice(start, end);

    expect(failureSource).toContain("AND attempt_count = ?");
    expect(failureSource).toContain(
      "[nextStatus, errorMessage.slice(0, 1000), jobId, attemptCount]",
    );
  });

  it("keeps stale PROCESSING reclaim behavior", () => {
    expect(repository).toContain("DATE_SUB(CURRENT_TIMESTAMP(3), INTERVAL 15 MINUTE)");
    expect(repository).toContain("attempt_count = attempt_count + 1");
  });
});
