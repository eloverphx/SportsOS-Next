export type OverlayClockAnchor = {
  remainingMs: number;
  running: boolean;
  capturedAtMs: number;
};

export function deriveSmoothedRemainingMs(
  anchor: OverlayClockAnchor,
  nowMs: number,
): number {
  const remaining = Math.max(0, anchor.remainingMs);

  if (!anchor.running) {
    return remaining;
  }

  const elapsed = Math.max(
    0,
    nowMs - anchor.capturedAtMs,
  );

  return Math.max(0, remaining - elapsed);
}

export function formatOverlayClock(
  remainingMs: number,
): string {
  const clamped = Math.max(0, remainingMs);

  if (clamped < 60_000) {
    const tenths = Math.floor(clamped / 100);
    const seconds = Math.floor(tenths / 10);
    const decimal = tenths % 10;

    return `${seconds}.${decimal}`;
  }

  const totalSeconds = Math.floor(clamped / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}
