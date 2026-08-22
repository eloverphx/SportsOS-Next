import type {
  FastifyInstance,
} from "fastify";

import {
  evaluatePregameReadinessGate,
} from "./scoreboardPregameReadinessGate.js";

type Assignment = {
  gameId: string;
  deviceId: string;
};

export type PregameStartGateResult = {
  allowed: boolean;
  gameId: string;
  deviceId: string | null;
  risk:
    | "HEALTHY"
    | "WATCH"
    | "AT_RISK"
    | "OFFLINE"
    | "UNKNOWN";
  overrideApplied: boolean;
  reason: string | null;
};

async function assignedDeviceForGame(
  app: FastifyInstance,
  gameId: string,
): Promise<string | null> {
  const response =
    await app.inject({
      method: "GET",
      url:
        "/scoreboard-devices/assignments",
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return null;
  }

  try {
    const body =
      response.json() as {
        data?: {
          assignments?: Assignment[];
        };
        assignments?: Assignment[];
      };

    const assignments =
      body.data?.assignments ??
      body.assignments ??
      [];

    return (
      assignments.find(
        (item) =>
          item.gameId ===
          gameId,
      )?.deviceId ??
      null
    );
  } catch {
    return null;
  }
}

export async function evaluateGameStartReadiness(
  app: FastifyInstance,
  gameId: string,
): Promise<PregameStartGateResult> {
  const deviceId =
    await assignedDeviceForGame(
      app,
      gameId,
    );

  return evaluatePregameReadinessGate({
    gameId,
    deviceId,
  });
}
