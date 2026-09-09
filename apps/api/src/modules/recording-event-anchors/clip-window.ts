export interface HighlightClipWindow {
  readonly startMs: number;
  readonly endMs: number;
  readonly durationMs: number;
}

function assertNonNegativeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${label} must be a non-negative safe integer`);
  }
}

export function deriveEventClipWindow(input: {
  readonly recordingOffsetMs: number;
  readonly recordingDurationMs: number | null;
  readonly preRollMs?: number;
  readonly postRollMs?: number;
}): HighlightClipWindow {
  const preRollMs = input.preRollMs ?? 8_000;
  const postRollMs = input.postRollMs ?? 5_000;

  assertNonNegativeInteger(input.recordingOffsetMs, "recordingOffsetMs");

  assertNonNegativeInteger(preRollMs, "preRollMs");

  assertNonNegativeInteger(postRollMs, "postRollMs");

  if (input.recordingDurationMs !== null) {
    assertNonNegativeInteger(input.recordingDurationMs, "recordingDurationMs");
  }

  const anchorMs =
    input.recordingDurationMs === null
      ? input.recordingOffsetMs
      : Math.min(input.recordingOffsetMs, input.recordingDurationMs);

  const startMs = Math.max(0, anchorMs - preRollMs);

  const endMs =
    input.recordingDurationMs === null
      ? anchorMs + postRollMs
      : Math.min(input.recordingDurationMs, anchorMs + postRollMs);

  return {
    startMs,
    endMs,
    durationMs: Math.max(0, endMs - startMs),
  };
}
