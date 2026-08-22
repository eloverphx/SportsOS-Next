import type {
  ScoreboardControlInputEvent,
} from "@sportsos/core";

export type ScoreboardControlCommand =
  | {
      kind: "SCORE";
      side: "HOME" | "AWAY";
      delta: 1 | -1;
    }
  | {
      kind: "CLOCK";
      action:
        | "START"
        | "PAUSE"
        | "TOGGLE";
    }
  | {
      kind: "PERIOD";
      delta: 1 | -1;
    }
  | {
      kind: "HORN";
    };

export function mapScoreboardControlInputToCommand(
  event: ScoreboardControlInputEvent,
): ScoreboardControlCommand {
  switch (event.type) {
    case "SCORE_HOME_INCREMENT":
      return {
        kind: "SCORE",
        side: "HOME",
        delta: 1,
      };

    case "SCORE_HOME_DECREMENT":
      return {
        kind: "SCORE",
        side: "HOME",
        delta: -1,
      };

    case "SCORE_AWAY_INCREMENT":
      return {
        kind: "SCORE",
        side: "AWAY",
        delta: 1,
      };

    case "SCORE_AWAY_DECREMENT":
      return {
        kind: "SCORE",
        side: "AWAY",
        delta: -1,
      };

    case "CLOCK_START":
      return {
        kind: "CLOCK",
        action: "START",
      };

    case "CLOCK_PAUSE":
      return {
        kind: "CLOCK",
        action: "PAUSE",
      };

    case "CLOCK_TOGGLE":
      return {
        kind: "CLOCK",
        action: "TOGGLE",
      };

    case "PERIOD_INCREMENT":
      return {
        kind: "PERIOD",
        delta: 1,
      };

    case "PERIOD_DECREMENT":
      return {
        kind: "PERIOD",
        delta: -1,
      };

    case "HORN_TRIGGER":
      return {
        kind: "HORN",
      };
  }
}
