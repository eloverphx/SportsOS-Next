export const SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION =
  1 as const;

export type ScoreboardControlInputType =
  | "SCORE_HOME_INCREMENT"
  | "SCORE_HOME_DECREMENT"
  | "SCORE_AWAY_INCREMENT"
  | "SCORE_AWAY_DECREMENT"
  | "CLOCK_TOGGLE"
  | "CLOCK_START"
  | "CLOCK_PAUSE"
  | "PERIOD_INCREMENT"
  | "PERIOD_DECREMENT"
  | "HORN_TRIGGER";

export type ScoreboardControlInputEvent = {
  protocolVersion:
    typeof SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION;
  inputId: string;
  deviceId: string;
  type: ScoreboardControlInputType;
  occurredAt: string;
  sequence: number;
};

export type ScoreboardControlInputDisposition =
  | "ACCEPTED"
  | "REJECTED"
  | "IGNORED_DUPLICATE";

export type ScoreboardControlInputAck = {
  inputId: string;
  deviceId: string;
  disposition: ScoreboardControlInputDisposition;
  reason: string | null;
  authoritativeGameId: string | null;
  processedAt: string;
};

export function isScoreboardControlInputType(
  value: string,
): value is ScoreboardControlInputType {
  return (
    value === "SCORE_HOME_INCREMENT" ||
    value === "SCORE_HOME_DECREMENT" ||
    value === "SCORE_AWAY_INCREMENT" ||
    value === "SCORE_AWAY_DECREMENT" ||
    value === "CLOCK_TOGGLE" ||
    value === "CLOCK_START" ||
    value === "CLOCK_PAUSE" ||
    value === "PERIOD_INCREMENT" ||
    value === "PERIOD_DECREMENT" ||
    value === "HORN_TRIGGER"
  );
}
