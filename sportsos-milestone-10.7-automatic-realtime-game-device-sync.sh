#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.7-automatic-realtime-game-device-sync"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps" \
  "$ROOT/apps/api"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

SYNC="apps/api/src/services/gameScoreboardSync.ts"
AUTO="apps/api/src/services/automaticGameScoreboardSync.ts"
ROUTE="apps/api/src/routes/scoreboardDevices.ts"
TEST="apps/api/test/automatic-game-scoreboard-sync-10.7.test.ts"

for file in "$SYNC" "$ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required Milestone 10.6 file missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$AUTO")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$AUTO")" \
  "$(dirname "$TEST")"

for file in "$AUTO" "$ROUTE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$AUTO" <<'EOF'
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

  public getAssignment(
    gameId: string,
  ): GameScoreboardAssignment | null {
    return (
      this.assignments.get(gameId) ??
      null
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDevices.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("AutomaticGameScoreboardSync")) {
  const anchor = `import {
  GameScoreboardSyncService,
  type AuthoritativeGameSnapshot,
} from "../services/gameScoreboardSync.js";`;

  if (!text.includes(anchor)) {
    throw new Error(
      "GameScoreboardSyncService import anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}
import {
  AutomaticGameScoreboardSync,
} from "../services/automaticGameScoreboardSync.js";`,
  );
}

if (!text.includes("const automaticSync =")) {
  const anchor = `const syncService =
  new GameScoreboardSyncService(gateway);`;

  if (!text.includes(anchor)) {
    throw new Error(
      "syncService instance anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}
const automaticSync =
  new AutomaticGameScoreboardSync(syncService);`,
  );
}

if (
  !text.includes(
    '"/scoreboard-devices/assignments"',
  )
) {
  const closing = text.lastIndexOf("\n}");

  if (closing < 0) {
    throw new Error(
      "Could not locate scoreboard routes closing brace.",
    );
  }

  const block = `

  app.get(
    "/scoreboard-devices/assignments",
    async () => ({
      success: true,
      data: {
        assignments:
          automaticSync.listAssignments(),
      },
    }),
  );

  app.put<{
    Params: {
      gameId: string;
    };
    Body: {
      deviceId: string;
    };
  }>(
    "/scoreboard-devices/assignments/:gameId",
    async (request, reply) => {
      try {
        const assignment =
          automaticSync.assign(
            request.params.gameId,
            request.body.deviceId,
          );

        return reply.send({
          success: true,
          data: {
            assignment,
          },
        });
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "INVALID_SCOREBOARD_ASSIGNMENT",
              message:
                error instanceof Error
                  ? error.message
                  : "Invalid scoreboard assignment.",
            },
          });
      }
    },
  );

  app.delete<{
    Params: {
      gameId: string;
    };
  }>(
    "/scoreboard-devices/assignments/:gameId",
    async (request) => ({
      success: true,
      data: {
        removed:
          automaticSync.unassign(
            request.params.gameId,
          ),
      },
    }),
  );

  app.post<{
    Body: AuthoritativeGameSnapshot;
  }>(
    "/scoreboard-devices/realtime-sync",
    async (request, reply) => {
      try {
        const result =
          await automaticSync
            .handleAuthoritativeSnapshot(
              request.body,
            );

        return reply.send({
          success: true,
          data: {
            result,
          },
        });
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "SCOREBOARD_REALTIME_SYNC_FAILED",
              message:
                error instanceof Error
                  ? error.message
                  : "Realtime scoreboard synchronization failed.",
            },
          });
      }
    },
  );`;

  text =
    text.slice(0, closing) +
    block +
    text.slice(closing);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import {
  AutomaticGameScoreboardSync,
} from "../src/services/automaticGameScoreboardSync.js";

describe("Milestone 10.7 automatic realtime game-to-device sync", () => {
  it("assigns a game to a scoreboard device", () => {
    const service =
      new AutomaticGameScoreboardSync(
        {
          sync: vi.fn(),
        } as never,
      );

    expect(
      service.assign(
        "game-1",
        "scoreboard-1",
      ),
    ).toMatchObject({
      gameId: "game-1",
      deviceId: "scoreboard-1",
    });
  });

  it("automatically syncs changed authoritative state", async () => {
    const sync = vi
      .fn()
      .mockResolvedValue("cmd-1");

    const service =
      new AutomaticGameScoreboardSync(
        { sync } as never,
      );

    service.assign(
      "game-1",
      "scoreboard-1",
    );

    const result =
      await service
        .handleAuthoritativeSnapshot({
          gameId: "game-1",
          homeScore: 2,
          awayScore: 1,
          period: 2,
          clock: {
            remainingMs: 65000,
            running: true,
          },
        });

    expect(result).toEqual({
      synced: true,
      gameId: "game-1",
      deviceId: "scoreboard-1",
      commandId: "cmd-1",
    });

    expect(sync).toHaveBeenCalledTimes(1);
  });

  it("does not resend identical state", async () => {
    const sync = vi
      .fn()
      .mockResolvedValue("cmd-1");

    const service =
      new AutomaticGameScoreboardSync(
        { sync } as never,
      );

    service.assign(
      "game-1",
      "scoreboard-1",
    );

    const snapshot = {
      gameId: "game-1",
      homeScore: 2,
      awayScore: 1,
      period: 2,
      clock: {
        remainingMs: 65000,
        running: true,
      },
    };

    await service
      .handleAuthoritativeSnapshot(
        snapshot,
      );

    const second =
      await service
        .handleAuthoritativeSnapshot(
          snapshot,
        );

    expect(second).toEqual({
      synced: false,
      gameId: "game-1",
      reason: "UNCHANGED",
    });

    expect(sync).toHaveBeenCalledTimes(1);
  });

  it("does not sync games without a device assignment", async () => {
    const service =
      new AutomaticGameScoreboardSync(
        {
          sync: vi.fn(),
        } as never,
      );

    expect(
      await service
        .handleAuthoritativeSnapshot({
          gameId: "game-unassigned",
          homeScore: 0,
          awayScore: 0,
          period: 1,
          clock: {
            remainingMs: 600000,
            running: false,
          },
        }),
    ).toEqual({
      synced: false,
      gameId: "game-unassigned",
      reason:
        "NO_DEVICE_ASSIGNED",
    });
  });

  it("exposes assignment and realtime-sync API routes", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      '"/scoreboard-devices/assignments"',
    );
    expect(route).toContain(
      '"/scoreboard-devices/assignments/:gameId"',
    );
    expect(route).toContain(
      '"/scoreboard-devices/realtime-sync"',
    );
    expect(route).toContain(
      "handleAuthoritativeSnapshot",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.7 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - game -> scoreboard assignment registry"
echo "  - automatic authoritative snapshot synchronization"
echo "  - unchanged-state deduplication"
echo "  - GET /scoreboard-devices/assignments"
echo "  - PUT /scoreboard-devices/assignments/:gameId"
echo "  - DELETE /scoreboard-devices/assignments/:gameId"
echo "  - POST /scoreboard-devices/realtime-sync"
echo "  - Milestone 10.7 tests"
echo
echo "Important:"
echo "  - This milestone provides the automatic sync coordinator and ingress."
echo "  - The authoritative game-event pipeline remains the source of snapshots."
echo "  - Milestone 10.8 will bind that pipeline directly so no caller needs to POST realtime-sync manually."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
echo
echo "Next after green:"
echo "  Milestone 10.8 - Authoritative Game Event Pipeline Binding"
