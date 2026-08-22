import type {
  AuthoritativeGameSnapshot,
} from "./gameScoreboardSync.js";
import {
  AutomaticGameScoreboardSync,
} from "./automaticGameScoreboardSync.js";

export type ScoreboardRecoveryResult =
  | {
      reconciled: true;
      deviceId: string;
      gameId: string;
      commandId: string;
    }
  | {
      reconciled: false;
      deviceId: string;
      reason:
        | "NO_ASSIGNED_GAME"
        | "NO_AUTHORITATIVE_SNAPSHOT";
    };

export class ScoreboardDeviceRecoveryService {
  private readonly latestSnapshots =
    new Map<string, AuthoritativeGameSnapshot>();

  public constructor(
    private readonly automaticSync:
      AutomaticGameScoreboardSync,
  ) {}

  public rememberAuthoritativeSnapshot(
    snapshot: AuthoritativeGameSnapshot,
  ): void {
    this.latestSnapshots.set(
      snapshot.gameId,
      {
        gameId: snapshot.gameId,
        homeScore: snapshot.homeScore,
        awayScore: snapshot.awayScore,
        period: snapshot.period,
        clock: {
          remainingMs:
            snapshot.clock.remainingMs,
          running:
            snapshot.clock.running,
        },
      },
    );
  }

  public getRememberedSnapshot(
    gameId: string,
  ): AuthoritativeGameSnapshot | null {
    return (
      this.latestSnapshots.get(gameId) ??
      null
    );
  }

  public async reconcileDevice(
    deviceId: string,
  ): Promise<ScoreboardRecoveryResult> {
    const assignment =
      this.automaticSync
        .listAssignments()
        .find(
          (item) =>
            item.deviceId === deviceId,
        );

    if (!assignment) {
      return {
        reconciled: false,
        deviceId,
        reason: "NO_ASSIGNED_GAME",
      };
    }

    const snapshot =
      this.latestSnapshots.get(
        assignment.gameId,
      );

    if (!snapshot) {
      return {
        reconciled: false,
        deviceId,
        reason:
          "NO_AUTHORITATIVE_SNAPSHOT",
      };
    }

    this.automaticSync.invalidate(
      assignment.gameId,
    );

    const result =
      await this.automaticSync
        .handleAuthoritativeSnapshot(
          snapshot,
        );

    if (!result.synced) {
      return {
        reconciled: false,
        deviceId,
        reason:
          "NO_AUTHORITATIVE_SNAPSHOT",
      };
    }

    return {
      reconciled: true,
      deviceId,
      gameId:
        assignment.gameId,
      commandId:
        result.commandId,
    };
  }
}
