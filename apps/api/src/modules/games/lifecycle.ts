import { z } from "zod";
import type { ScoreAction } from "./schemas.js";
import type { Game } from "./types.js";

export const gameLifecycleCommands = [
  "startGame",
  "endPeriod",
  "beginIntermission",
  "startNextPeriod",
  "startOvertime",
  "finishGame",
] as const;

export type GameLifecycleCommand = (typeof gameLifecycleCommands)[number];

export const gameLifecycleCommandSchema = z.object({
  command: z.enum(gameLifecycleCommands),
  commandId: z
    .string()
    .regex(/^[A-Za-z0-9._:-]{8,80}$/)
    .optional(),
});

export class GameLifecycleError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GameLifecycleError";
  }
}

type LifecycleGame = Pick<
  Game,
  "status" | "gamePhase" | "period" | "regulationPeriods" | "clockRemainingMs"
>;

export function resolveLifecycleAction(
  game: LifecycleGame,
  command: GameLifecycleCommand,
): ScoreAction {
  switch (command) {
    case "startGame":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError("A final game cannot be restarted");
      }
      if (game.gamePhase !== "PREGAME") {
        throw new GameLifecycleError("The game has already started");
      }
      return { action: "startClock" };

    case "endPeriod":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError("A final game has no active period");
      }
      if (game.gamePhase === "INTERMISSION") {
        throw new GameLifecycleError("The game is already in intermission");
      }
      if (game.clockRemainingMs > 0) {
        throw new GameLifecycleError(
          "The game clock must be at 0:00 before ending the period",
        );
      }

      if (
        game.gamePhase === "REGULATION" &&
        game.period < game.regulationPeriods
      ) {
        return { action: "startIntermission" };
      }

      return { action: "pauseClock" };

    case "beginIntermission":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError(
          "Intermission cannot start after the game is final",
        );
      }
      if (game.gamePhase === "INTERMISSION") {
        throw new GameLifecycleError("The game is already in intermission");
      }
      if (game.clockRemainingMs > 0) {
        throw new GameLifecycleError(
          "Intermission can start only when the game clock is at 0:00",
        );
      }
      return { action: "startIntermission" };

    case "startNextPeriod":
      return { action: "nextPeriod" };

    case "startOvertime":
      return { action: "startOvertime" };

    case "finishGame":
      if (game.status === "FINAL" || game.gamePhase === "FINAL") {
        throw new GameLifecycleError("The game is already final");
      }
      return { action: "finishGame" };
  }
}
