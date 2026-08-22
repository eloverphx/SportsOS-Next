import type {
  FastifyInstance,
} from "fastify";
import { triggerPhysicalHornOutput } from "./scoreboardPhysicalHornOutput.js";

import type {
  ScoreboardControlInputEvent,
} from "@sportsos/core";

import {
  mapScoreboardControlInputToCommand,
  type ScoreboardControlCommand,
} from "./scoreboardControlCommandBinding.js";

export type PhysicalControlExecutionResult = {
  executed: boolean;
  statusCode: number;
  authoritativeGameId: string;
  command: ScoreboardControlCommand;
  responseBody: unknown;
  reason: string | null;
};

type RouteCandidate = {
  method: "POST" | "PUT" | "PATCH";
  route: string;
  payload:
    | Record<string, unknown>
    | null;
};

function routeUrl(
  route: string,
  gameId: string,
): string {
  return route
    .replace(
      ":gameId",
      encodeURIComponent(gameId),
    )
    .replace(
      ":id",
      encodeURIComponent(gameId),
    );
}

function candidatesFor(
  gameId: string,
  command: ScoreboardControlCommand,
): RouteCandidate[] {
  /*
   * These candidate contracts are intentionally limited to the existing
   * SportsOS game API shapes used across prior milestones. The adapter never
   * edits game state directly; it re-enters Fastify through app.inject().
   *
   * We stop after the first non-404 response so the same physical action
   * cannot be applied twice.
   */
  if (command.kind === "SCORE") {
    return [
      {
        method: "POST",
        route:
          "/games/:gameId/score",
        payload: {
          side:
            command.side.toLowerCase(),
          delta:
            command.delta,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/command",
        payload: {
          command:
            command.delta > 0
              ? command.side === "HOME"
                ? "incrementHomeScore"
                : "incrementAwayScore"
              : command.side === "HOME"
                ? "decrementHomeScore"
                : "decrementAwayScore",
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/commands",
        payload: {
          command:
            command.delta > 0
              ? command.side === "HOME"
                ? "incrementHomeScore"
                : "incrementAwayScore"
              : command.side === "HOME"
                ? "decrementHomeScore"
                : "decrementAwayScore",
        },
      },
    ];
  }

  if (command.kind === "CLOCK") {
    const commandName =
      command.action === "START"
        ? "startClock"
        : command.action === "PAUSE"
          ? "pauseClock"
          : "toggleClock";

    return [
      {
        method: "POST",
        route:
          "/games/:gameId/clock",
        payload: {
          command:
            commandName,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/command",
        payload: {
          command:
            commandName,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/commands",
        payload: {
          command:
            commandName,
        },
      },
    ];
  }

  if (command.kind === "PERIOD") {
    return [
      {
        method: "POST",
        route:
          "/games/:gameId/period",
        payload: {
          delta:
            command.delta,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/command",
        payload: {
          command:
            command.delta > 0
              ? "incrementPeriod"
              : "decrementPeriod",
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/commands",
        payload: {
          command:
            command.delta > 0
              ? "incrementPeriod"
              : "decrementPeriod",
        },
      },
    ];
  }

  /*
   * Horn is a physical side-effect, not a persistent game-state mutation.
   * It is acknowledged here and is bound to the scoreboard device command
   * transport in a later milestone.
   */
  return [];
}

export async function executePhysicalScoreboardControl(
  app: FastifyInstance,
  gameId: string,
  event: ScoreboardControlInputEvent,
): Promise<PhysicalControlExecutionResult> {
  const command =
    mapScoreboardControlInputToCommand(
      event,
    );

  if (command.kind === "HORN") {
    /*
     * Horn is a physical side-effect rather than persistent game state.
     * Resolve the live device assignment and re-enter the existing scoreboard
     * device command API so MQTT/device authorization stays centralized.
     */
    const assignment =
      (
        await app.inject({
          method: "GET",
          url:
            "/scoreboard-devices/assignments",
        })
      );

    let deviceId:
      string | null =
        null;

    try {
      const payload =
        assignment.json() as {
          data?: {
            assignments?: Array<{
              gameId?: string;
              deviceId?: string;
            }>;
          };
          assignments?: Array<{
            gameId?: string;
            deviceId?: string;
          }>;
        };

      const assignments =
        payload.data?.assignments ??
        payload.assignments ??
        [];

      deviceId =
        assignments.find(
          (item) =>
            item.gameId ===
            gameId,
        )?.deviceId ??
        null;
    } catch {
      deviceId =
        null;
    }

    if (!deviceId) {
      return {
        executed: false,
        statusCode: 409,
        authoritativeGameId:
          gameId,
        command,
        responseBody: null,
        reason:
          "No scoreboard device assignment is available for horn output.",
      };
    }

    const horn =
      await triggerPhysicalHornOutput(
        app,
        deviceId,
      );

    return {
      executed:
        horn.triggered,
      statusCode:
        horn.statusCode,
      authoritativeGameId:
        gameId,
      command,
      responseBody:
        horn.responseBody,
      reason:
        horn.reason,
    };
  }

  const candidates =
    candidatesFor(
      gameId,
      command,
    );

  for (const candidate of candidates) {
    const response =
      await app.inject({
        method:
          candidate.method,
        url:
          routeUrl(
            candidate.route,
            gameId,
          ),
        payload:
          candidate.payload ??
          undefined,
      });

    if (response.statusCode === 404) {
      continue;
    }

    let responseBody: unknown =
      response.body;

    try {
      responseBody =
        response.json();
    } catch {
      // Keep raw response body.
    }

    return {
      executed:
        response.statusCode >= 200 &&
        response.statusCode < 300,
      statusCode:
        response.statusCode,
      authoritativeGameId:
        gameId,
      command,
      responseBody,
      reason:
        response.statusCode >= 200 &&
        response.statusCode < 300
          ? null
          : "Authoritative game mutation rejected.",
    };
  }

  return {
    executed: false,
    statusCode: 501,
    authoritativeGameId:
      gameId,
    command,
    responseBody: null,
    reason:
      "No compatible authoritative game mutation route was found.",
  };
}
