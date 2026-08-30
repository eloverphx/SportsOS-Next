import {
  recordBroadcastCoordinatorAudit,
} from "./broadcastCoordinatorAudit.js";

import {
  prepareBroadcastSession,
  reconcileBroadcastCoordinator,
  stopCoordinatedBroadcast,
} from "./broadcastSessionCoordinator.js";

import {
  evaluateBroadcastResilienceSupervisor,
} from "./broadcastResilienceSupervisor.js";

export type ControlledRecoveryRequest = {
  gameId: string;
  operator: string;
  approveDestructive: boolean;
  coordinatorIntent: string;
  runtimeStatus: string;
  lastActivityAt: string | null;
  stateAgeMs: number;
};

export type ControlledRecoveryResult = {
  executed: boolean;
  action: string;
  message: string;
};

export async function executeControlledBroadcastRecovery(
  input: ControlledRecoveryRequest,
): Promise<ControlledRecoveryResult> {
  const operator =
    input.operator.trim();

  if (!operator) {
    throw new Error(
      "Operator name is required.",
    );
  }

  const decision =
    evaluateBroadcastResilienceSupervisor({
      coordinatorIntent:
        input.coordinatorIntent,
      runtimeStatus:
        input.runtimeStatus,
      lastActivityAt:
        input.lastActivityAt,
      stateAgeMs:
        input.stateAgeMs,
    });

  recordBroadcastCoordinatorAudit({
    gameId:
      input.gameId,
    type:
      "RECOVERY_REQUESTED",
    detail:
      `${operator}: ${decision.recovery.action}`,
  });

  if (
    decision.recovery.action ===
      "require-operator-review"
  ) {
    recordBroadcastCoordinatorAudit({
      gameId:
        input.gameId,
      type:
        "RECOVERY_REFUSED",
      detail:
        `${operator}: supervisor requires operator review.`,
    });

    return {
      executed:
        false,
      action:
        decision.recovery.action,
      message:
        "Recovery was not executed because the supervisor requires operator review.",
    };
  }

  if (
    decision.recovery.destructive &&
    !input.approveDestructive
  ) {
    recordBroadcastCoordinatorAudit({
      gameId:
        input.gameId,
      type:
        "RECOVERY_REFUSED",
      detail:
        `${operator}: destructive recovery requires explicit approval.`,
    });

    return {
      executed:
        false,
      action:
        decision.recovery.action,
      message:
        "Destructive recovery requires explicit operator approval.",
    };
  }

  switch (
    decision.recovery.action
  ) {
    case "request-controlled-start":
      prepareBroadcastSession(
        input.gameId,
      );

      recordBroadcastCoordinatorAudit({
        gameId:
          input.gameId,
        type:
          "RECOVERY_EXECUTED",
        detail:
          `${operator}: prepared controlled restart path.`,
      });

      return {
        executed:
          true,
        action:
          decision.recovery.action,
        message:
          "Controlled start recovery prepared. Final start still requires the normal guarded start flow.",
      };

    case "request-controlled-stop":
      await stopCoordinatedBroadcast(
        input.gameId,
      );

      recordBroadcastCoordinatorAudit({
        gameId:
          input.gameId,
        type:
          "RECOVERY_EXECUTED",
        detail:
          `${operator}: controlled stop executed.`,
      });

      return {
        executed:
          true,
        action:
          decision.recovery.action,
        message:
          "Controlled stop recovery executed.",
      };

    case "reconcile-to-idle":
      await reconcileBroadcastCoordinator(
        input.gameId,
      );

      recordBroadcastCoordinatorAudit({
        gameId:
          input.gameId,
        type:
          "RECOVERY_EXECUTED",
        detail:
          `${operator}: non-destructive reconciliation executed.`,
      });

      return {
        executed:
          true,
        action:
          decision.recovery.action,
        message:
          "Coordinator state reconciled.",
      };

    case "observe":
    case "none":
      return {
        executed:
          false,
        action:
          decision.recovery.action,
        message:
          "No recovery action is required.",
      };
  }
}
