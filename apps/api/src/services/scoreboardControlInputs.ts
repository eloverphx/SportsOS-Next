import type {
  ScoreboardControlInputAck,
  ScoreboardControlInputEvent,
} from "@sportsos/core";
import { mapScoreboardControlInputToCommand } from "./scoreboardControlCommandBinding.js";

import type {
  AutomaticGameScoreboardSync,
} from "./automaticGameScoreboardSync.js";

const recentInputs =
  new Map<
    string,
    {
      sequence: number;
      processedAt: string;
    }
  >();

export function processScoreboardControlInput(
  event: ScoreboardControlInputEvent,
  automaticSync: AutomaticGameScoreboardSync,
): ScoreboardControlInputAck {
  const processedAt =
    new Date().toISOString();

  const assignment =
    automaticSync
      .getAssignmentByDeviceId(
        event.deviceId,
      );

  const previous =
    recentInputs.get(
      event.deviceId,
    );

  if (
    previous &&
    event.sequence <=
      previous.sequence
  ) {
    return {
      inputId:
        event.inputId,
      deviceId:
        event.deviceId,
      disposition:
        "IGNORED_DUPLICATE",
      reason:
        "Sequence already processed.",
      authoritativeGameId:
        assignment?.gameId ?? null,
      processedAt,
    };
  }

  if (!assignment) {
    return {
      inputId:
        event.inputId,
      deviceId:
        event.deviceId,
      disposition:
        "REJECTED",
      reason:
        "Scoreboard device is not assigned to a game.",
      authoritativeGameId:
        null,
      processedAt,
    };
  }

  recentInputs.set(
    event.deviceId,
    {
      sequence:
        event.sequence,
      processedAt,
    },
  );

  return {
    inputId:
      event.inputId,
    deviceId:
      event.deviceId,
    disposition:
      "ACCEPTED",
    reason:
      null,
    authoritativeGameId:
      assignment.gameId,
    processedAt,
    command:
      mapScoreboardControlInputToCommand(
        event,
      ),
  } as ScoreboardControlInputAck & {
    command: ReturnType<
      typeof mapScoreboardControlInputToCommand
    >;
  };
}
