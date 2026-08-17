export type GameStartTiming = {
  scheduledStart: string | null;
  actualStart: string | null;
  delayMs: number | null;
  delayMinutes: number | null;
  state:
    | "NOT_SCHEDULED"
    | "NOT_STARTED"
    | "EARLY"
    | "ON_TIME"
    | "DELAYED";
};

export function computeGameStartTiming(
  scheduledStart: string | null,
  actualStart: string | null,
): GameStartTiming {
  if (!scheduledStart) {
    return {
      scheduledStart: null,
      actualStart,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_SCHEDULED",
    };
  }

  const scheduledMs = new Date(scheduledStart).getTime();

  if (!Number.isFinite(scheduledMs)) {
    throw new Error("Invalid scheduled start timestamp.");
  }

  if (!actualStart) {
    return {
      scheduledStart,
      actualStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_STARTED",
    };
  }

  const actualMs = new Date(actualStart).getTime();

  if (!Number.isFinite(actualMs)) {
    throw new Error("Invalid actual start timestamp.");
  }

  const delayMs = actualMs - scheduledMs;
  const delayMinutes = Math.round((delayMs / 60_000) * 10) / 10;

  let state: GameStartTiming["state"];

  if (Math.abs(delayMs) < 30_000) {
    state = "ON_TIME";
  } else if (delayMs < 0) {
    state = "EARLY";
  } else {
    state = "DELAYED";
  }

  return {
    scheduledStart,
    actualStart,
    delayMs,
    delayMinutes,
    state,
  };
}

export function formatDelayLabel(
  timing: GameStartTiming,
): string {
  switch (timing.state) {
    case "NOT_SCHEDULED":
      return "Not scheduled";
    case "NOT_STARTED":
      return "Not started";
    case "ON_TIME":
      return "On time";
    case "EARLY":
      return `${Math.abs(timing.delayMinutes ?? 0)} min early`;
    case "DELAYED":
      return `${timing.delayMinutes ?? 0} min late`;
  }
}
