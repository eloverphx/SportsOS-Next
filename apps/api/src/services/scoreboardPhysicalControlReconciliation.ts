import type {
  FastifyInstance,
} from "fastify";

import type {
  AutomaticGameScoreboardSync,
  GameScoreboardAssignment,
} from "./automaticGameScoreboardSync.js";

export type PhysicalControlReconciliationResult = {
  reconciled: boolean;
  authoritativeGameId: string;
  deviceId: string;
  reason: string | null;
  responseBody: unknown;
};

function gameSnapshotUrls(
  gameId: string,
): string[] {
  const encoded =
    encodeURIComponent(
      gameId,
    );

  return [
    `/games/${encoded}`,
    `/games/${encoded}/snapshot`,
    `/games/${encoded}/state`,
  ];
}

export async function reconcilePhysicalControlResult(
  app: FastifyInstance,
  automaticSync: AutomaticGameScoreboardSync,
  assignment: GameScoreboardAssignment,
): Promise<PhysicalControlReconciliationResult> {
  let lastBody: unknown =
    null;

  for (
    const url of gameSnapshotUrls(
      assignment.gameId,
    )
  ) {
    const response =
      await app.inject({
        method: "GET",
        url,
      });

    if (response.statusCode === 404) {
      continue;
    }

    let body: unknown =
      response.body;

    try {
      body =
        response.json();
    } catch {
      // Keep raw body for diagnostics.
    }

    lastBody =
      body;

    if (
      response.statusCode < 200 ||
      response.statusCode >= 300
    ) {
      return {
        reconciled: false,
        authoritativeGameId:
          assignment.gameId,
        deviceId:
          assignment.deviceId,
        reason:
          "Authoritative game snapshot request was rejected.",
        responseBody:
          body,
      };
    }

    /*
     * Do not reimplement game snapshot construction here.
     * Existing automatic scoreboard sync remains responsible for consuming
     * authoritative snapshots produced by the game engine. This reconciliation
     * step intentionally invalidates the dedupe fingerprint so the next
     * authoritative snapshot is guaranteed to reach the physical scoreboard.
     */
    automaticSync.invalidate(
      assignment.gameId,
    );

    return {
      reconciled: true,
      authoritativeGameId:
        assignment.gameId,
      deviceId:
        assignment.deviceId,
      reason:
        null,
      responseBody:
        body,
    };
  }

  /*
   * Even when there is no dedicated GET snapshot route, invalidating the
   * existing sync fingerprint is safe and ensures the next authoritative
   * game-state publication will not be deduplicated.
   */
  automaticSync.invalidate(
    assignment.gameId,
  );

  return {
    reconciled: true,
    authoritativeGameId:
      assignment.gameId,
    deviceId:
      assignment.deviceId,
    reason:
      "No direct game snapshot route found; realtime sync cache invalidated.",
    responseBody:
      lastBody,
  };
}
