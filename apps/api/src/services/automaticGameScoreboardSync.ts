import type {
  AuthoritativeGameSnapshot,
} from "./gameScoreboardSync.js";
import {
  GameScoreboardSyncService,
} from "./gameScoreboardSync.js";

export type GameScoreboardAssignment = {
  gameId: string;
  deviceId: string;
  assignedAt: string;
};

export type AutomaticSyncResult =
  | {
      synced: true;
      gameId: string;
      deviceId: string;
      commandId: string;
    }
  | {
      synced: false;
      gameId: string;
      reason: "NO_DEVICE_ASSIGNED" | "UNCHANGED";
    };

function snapshotFingerprint(
  snapshot: AuthoritativeGameSnapshot,
): string {
  return JSON.stringify({
    gameId: snapshot.gameId,
    homeScore: snapshot.homeScore,
    awayScore: snapshot.awayScore,
    period: snapshot.period,
    remainingMs:
      snapshot.clock.remainingMs,
    running:
      snapshot.clock.running,
  });
}

export class AutomaticGameScoreboardSync {
  private readonly assignments =
    new Map<string, GameScoreboardAssignment>();

  private readonly lastFingerprint =
    new Map<string, string>();

  public constructor(
    private readonly syncService:
      GameScoreboardSyncService,
  ) {}

  public assign(
    gameId: string,
    deviceId: string,
  ): GameScoreboardAssignment {
    const normalizedGameId =
      gameId.trim();
    const normalizedDeviceId =
      deviceId.trim();

    if (!normalizedGameId) {
      throw new Error(
        "gameId is required.",
      );
    }

    if (!normalizedDeviceId) {
      throw new Error(
        "deviceId is required.",
      );
    }

    const assignment: GameScoreboardAssignment = {
      gameId: normalizedGameId,
      deviceId: normalizedDeviceId,
      assignedAt:
        new Date().toISOString(),
    };

    this.assignments.set(
      normalizedGameId,
      assignment,
    );

    this.lastFingerprint.delete(
      normalizedGameId,
    );

    return assignment;
  }

  public unassign(
    gameId: string,
  ): boolean {
    this.lastFingerprint.delete(
      gameId,
    );

    return this.assignments.delete(
      gameId,
    );
  }

  public invalidate(
    gameId: string,
  ): void {
    this.lastFingerprint.delete(
      gameId,
    );
  }

  public getAssignment(
    gameId: string,
  ): GameScoreboardAssignment | null {
    return (
      this.assignments.get(gameId) ??
      null
    );
  }

  public getAssignmentByDeviceId(
    deviceId: string,
  ): GameScoreboardAssignment | null {
    const normalizedDeviceId =
      deviceId.trim();

    return (
      this.listAssignments().find(
        (assignment) =>
          assignment.deviceId ===
          normalizedDeviceId,
      ) ?? null
    );
  }

  public listAssignments():
    GameScoreboardAssignment[] {
    return Array.from(
      this.assignments.values(),
    );
  }

  public async handleAuthoritativeSnapshot(
    snapshot: AuthoritativeGameSnapshot,
  ): Promise<AutomaticSyncResult> {
    const assignment =
      this.assignments.get(
        snapshot.gameId,
      );

    if (!assignment) {
      return {
        synced: false,
        gameId: snapshot.gameId,
        reason: "NO_DEVICE_ASSIGNED",
      };
    }

    const fingerprint =
      snapshotFingerprint(snapshot);

    if (
      this.lastFingerprint.get(
        snapshot.gameId,
      ) === fingerprint
    ) {
      return {
        synced: false,
        gameId: snapshot.gameId,
        reason: "UNCHANGED",
      };
    }

    const commandId =
      await this.syncService.sync(
        snapshot,
        assignment.deviceId,
      );

    this.lastFingerprint.set(
      snapshot.gameId,
      fingerprint,
    );

    return {
      synced: true,
      gameId: snapshot.gameId,
      deviceId:
        assignment.deviceId,
      commandId,
    };
  }
}
