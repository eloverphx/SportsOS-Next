import type { RecordingStatus } from "../recordings/repository.js";

export function recordingCanQueueClipJobs(status: RecordingStatus): boolean {
  return status === "RECORDING" || status === "PROCESSING" || status === "READY";
}

export function assertValidClipWindow(startMs: number, endMs: number): void {
  if (
    !Number.isSafeInteger(startMs) ||
    !Number.isSafeInteger(endMs) ||
    startMs < 0 ||
    endMs <= startMs
  ) {
    throw new RangeError(
      "Clip window must contain safe non-negative integers with endMs greater than startMs",
    );
  }
}
