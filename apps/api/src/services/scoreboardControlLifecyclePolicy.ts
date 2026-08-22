import type {
  FastifyInstance,
} from "fastify";

export type LifecycleControlDecision = {
  allowed: boolean;
  status: string | null;
  reason: string | null;
};

function extractStatus(
  payload: unknown,
): string | null {
  if (
    typeof payload !== "object" ||
    payload === null
  ) {
    return null;
  }

  const value =
    payload as Record<
      string,
      unknown
    >;

  const candidates: unknown[] = [
    value.status,
    value.lifecycleStatus,
    value.gameStatus,
    value.state,
    (
      typeof value.data ===
        "object" &&
      value.data !==
        null
        ? (
            value.data as Record<
              string,
              unknown
            >
          ).status
        : null
    ),
    (
      typeof value.data ===
        "object" &&
      value.data !==
        null
        ? (
            value.data as Record<
              string,
              unknown
            >
          ).lifecycleStatus
        : null
    ),
  ];

  for (
    const candidate of candidates
  ) {
    if (
      typeof candidate ===
        "string" &&
      candidate.trim()
    ) {
      return candidate
        .trim()
        .toUpperCase();
    }
  }

  return null;
}

function isActiveStatus(
  status: string,
): boolean {
  return [
    "LIVE",
    "IN_PROGRESS",
    "STARTED",
    "ACTIVE",
    "RUNNING",
  ].includes(status);
}

function isTerminalStatus(
  status: string,
): boolean {
  return [
    "FINAL",
    "FINISHED",
    "COMPLETED",
    "CANCELLED",
    "CANCELED",
    "POSTPONED",
  ].includes(status);
}

export async function evaluateGameLifecyclePhysicalControlPolicy(
  app: FastifyInstance,
  gameId: string,
): Promise<LifecycleControlDecision> {
  const encoded =
    encodeURIComponent(
      gameId,
    );

  const urls = [
    `/games/${encoded}`,
    `/games/${encoded}/state`,
    `/games/${encoded}/snapshot`,
  ];

  for (const url of urls) {
    const response =
      await app.inject({
        method: "GET",
        url,
      });

    if (
      response.statusCode ===
      404
    ) {
      continue;
    }

    if (
      response.statusCode <
        200 ||
      response.statusCode >=
        300
    ) {
      return {
        allowed: false,
        status: null,
        reason:
          "Unable to verify authoritative game lifecycle.",
      };
    }

    let body: unknown;

    try {
      body =
        response.json();
    } catch {
      body =
        response.body;
    }

    const status =
      extractStatus(
        body,
      );

    if (!status) {
      /*
       * Fail closed if the authoritative route exists but lifecycle cannot be
       * determined. This prevents physical controls from mutating a game whose
       * lifecycle is ambiguous.
       */
      return {
        allowed: false,
        status: null,
        reason:
          "Authoritative game lifecycle status is unavailable.",
      };
    }

    if (
      isActiveStatus(
        status,
      )
    ) {
      return {
        allowed: true,
        status,
        reason: null,
      };
    }

    if (
      isTerminalStatus(
        status,
      )
    ) {
      return {
        allowed: false,
        status,
        reason:
          `Physical controls are locked because game status is ${status}.`,
      };
    }

    return {
      allowed: false,
      status,
      reason:
        `Physical controls are locked until the game is active (status: ${status}).`,
    };
  }

  /*
   * If no supported authoritative read route exists, preserve existing
   * behavior rather than inventing lifecycle state. This makes the migration
   * non-breaking while still enforcing lifecycle where the API exposes it.
   */
  return {
    allowed: true,
    status: null,
    reason: null,
  };
}
