import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(
  path.resolve(__dirname, "../src/services/recordingClipWorker.ts"),
  "utf8",
);

describe("M37.17 clip object generation isolation", () => {
  it("names output objects with both job id and attempt generation", () => {
    expect(worker).toContain("`clips/${year}/job-${job.id}-attempt-${job.attemptCount}.mp4`");
    expect(worker).not.toContain("`clips/${year}/job-${job.id}.mp4`");
  });

  it("uses the same generation-scoped key for upload and completion", () => {
    expect(worker).toContain(
      "await minio.putObject(\n      config.storage.bucket,\n      objectKey,",
    );
    expect(worker).toContain("objectKey,");
    expect(worker).toContain("attemptCount: job.attemptCount");
  });

  it("only removes the current attempt object if completion fails", () => {
    expect(worker).toContain(
      "await minio.removeObject(config.storage.bucket, objectKey).catch(() => undefined)",
    );
  });

  it("preserves lease-fenced completion", () => {
    expect(worker).toContain("attemptCount: job.attemptCount");
  });
});
