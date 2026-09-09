import { describe, expect, it } from "vitest";
import {
  assertValidClipWindow,
  recordingCanQueueClipJobs,
} from "../src/modules/recording-clip-jobs/policy.js";

describe("Milestone 37.6 clip-job policy", () => {
  it("allows clip jobs while a recording is recording, processing, or ready", () => {
    expect(recordingCanQueueClipJobs("RECORDING")).toBe(true);
    expect(recordingCanQueueClipJobs("PROCESSING")).toBe(true);
    expect(recordingCanQueueClipJobs("READY")).toBe(true);
  });

  it("rejects recording states that cannot produce a clip", () => {
    expect(recordingCanQueueClipJobs("CREATED")).toBe(false);
    expect(recordingCanQueueClipJobs("FAILED")).toBe(false);
    expect(recordingCanQueueClipJobs("ARCHIVED")).toBe(false);
  });

  it("accepts a valid non-empty clip window", () => {
    expect(() => assertValidClipWindow(0, 13_000)).not.toThrow();
  });

  it("rejects negative, reversed, or empty windows", () => {
    expect(() => assertValidClipWindow(-1, 1)).toThrow(RangeError);

    expect(() => assertValidClipWindow(10, 10)).toThrow(RangeError);

    expect(() => assertValidClipWindow(20, 10)).toThrow(RangeError);
  });
});
