import {
  recordBroadcastCoordinatorAudit,
} from "./broadcastCoordinatorAudit.js";

import {
  runBroadcastCoordinatorSupervisorTick,
} from "./broadcastSessionCoordinator.js";

export type BroadcastCoordinatorSupervisorRuntimeOptions = {
  gameIds: () => string[];
  intervalMs?: number;
  onError?: (
    error: unknown,
    gameId: string,
  ) => void;
};

export function startBroadcastCoordinatorSupervisor(
  options: BroadcastCoordinatorSupervisorRuntimeOptions,
): () => void {
  const intervalMs =
    Math.max(
      1000,
      Math.min(
        options.intervalMs ??
        5000,
        60000,
      ),
    );

  let stopped = false;

  const runTick =
    async (): Promise<void> => {
      if (stopped) {
        return;
      }

      const gameIds =
        Array.from(
          new Set(
            options
              .gameIds()
              .map((gameId) => gameId.trim())
              .filter(Boolean),
          ),
        );

      for (const gameId of gameIds) {
        try {
          await runBroadcastCoordinatorSupervisorTick(
            gameId,
          );
        } catch (error) {
          recordBroadcastCoordinatorAudit({
            gameId,
            type:
              "SUPERVISOR_TICK_FAILED",
            detail:
              error instanceof Error
                ? error.message
                : "Unknown supervisor tick failure.",
          });

          options.onError?.(
            error,
            gameId,
          );
        }
      }
    };

  const timer =
    setInterval(
      () => {
        void runTick();
      },
      intervalMs,
    );

  recordBroadcastCoordinatorAudit({
    gameId:
      "__runtime__",
    type:
      "SUPERVISOR_STARTED",
    detail:
      `intervalMs=${intervalMs}`,
  });

  void runTick();

  return () => {
    if (stopped) {
      return;
    }

    stopped = true;
    clearInterval(timer);

    recordBroadcastCoordinatorAudit({
      gameId:
        "__runtime__",
      type:
        "SUPERVISOR_STOPPED",
      detail:
        `intervalMs=${intervalMs}`,
    });
  };
}
