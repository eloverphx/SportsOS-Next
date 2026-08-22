import type {
  FastifyInstance,
} from "fastify";

export type PhysicalHornOutputResult = {
  triggered: boolean;
  statusCode: number;
  deviceId: string;
  responseBody: unknown;
  reason: string | null;
};

type HornCandidate = {
  method: "POST";
  url: string;
  payload: Record<string, unknown>;
};

function candidatesFor(
  deviceId: string,
): HornCandidate[] {
  const encoded =
    encodeURIComponent(
      deviceId,
    );

  return [
    {
      method: "POST",
      url:
        `/scoreboard-devices/${encoded}/commands`,
      payload: {
        command: "TRIGGER_HORN",
      },
    },
    {
      method: "POST",
      url:
        `/scoreboard-devices/${encoded}/command`,
      payload: {
        command: "TRIGGER_HORN",
      },
    },
    {
      method: "POST",
      url:
        `/scoreboard-devices/${encoded}/horn`,
      payload: {
        action: "trigger",
      },
    },
  ];
}

export async function triggerPhysicalHornOutput(
  app: FastifyInstance,
  deviceId: string,
): Promise<PhysicalHornOutputResult> {
  for (
    const candidate of candidatesFor(
      deviceId,
    )
  ) {
    const response =
      await app.inject({
        method:
          candidate.method,
        url:
          candidate.url,
        payload:
          candidate.payload,
      });

    if (
      response.statusCode === 404
    ) {
      continue;
    }

    let responseBody: unknown =
      response.body;

    try {
      responseBody =
        response.json();
    } catch {
      // Preserve raw response for diagnostics.
    }

    return {
      triggered:
        response.statusCode >= 200 &&
        response.statusCode < 300,
      statusCode:
        response.statusCode,
      deviceId,
      responseBody,
      reason:
        response.statusCode >= 200 &&
        response.statusCode < 300
          ? null
          : "Scoreboard horn command was rejected.",
    };
  }

  return {
    triggered: false,
    statusCode: 501,
    deviceId,
    responseBody: null,
    reason:
      "No compatible scoreboard horn command route was found.",
  };
}
