#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.6-game-to-scoreboard-synchronization"
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

GATEWAY="apps/api/src/services/scoreboardDeviceGateway.ts"
SYNC="apps/api/src/services/gameScoreboardSync.ts"
ROUTE="apps/api/src/routes/scoreboardDevices.ts"
TEST="apps/api/test/game-scoreboard-sync-10.6.test.ts"

for file in "$GATEWAY" "$ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required Milestone 10.4 file missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$GATEWAY")" \
  "$BACKUP_DIR/$(dirname "$SYNC")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$SYNC")" \
  "$(dirname "$TEST")"

for file in "$GATEWAY" "$SYNC" "$ROUTE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$SYNC" <<'EOF'
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  type ScoreboardDeviceCommand,
} from "@sportsos/core";
import {
  ScoreboardDeviceGateway,
} from "./scoreboardDeviceGateway.js";

export type AuthoritativeGameSnapshot = {
  gameId: string;
  homeScore: number;
  awayScore: number;
  period: number | null;
  clock: {
    remainingMs: number;
    running: boolean;
  };
};

export function buildGameScoreboardSyncCommand(
  snapshot: AuthoritativeGameSnapshot,
  deviceId: string,
  commandId: string,
): ScoreboardDeviceCommand {
  if (!deviceId.trim()) {
    throw new Error("deviceId is required.");
  }

  if (!snapshot.gameId.trim()) {
    throw new Error("gameId is required.");
  }

  if (
    !Number.isInteger(snapshot.homeScore) ||
    snapshot.homeScore < 0
  ) {
    throw new Error(
      "homeScore must be a non-negative integer.",
    );
  }

  if (
    !Number.isInteger(snapshot.awayScore) ||
    snapshot.awayScore < 0
  ) {
    throw new Error(
      "awayScore must be a non-negative integer.",
    );
  }

  if (
    !Number.isFinite(snapshot.clock.remainingMs) ||
    snapshot.clock.remainingMs < 0
  ) {
    throw new Error(
      "remainingMs must be a non-negative number.",
    );
  }

  if (
    snapshot.period !== null &&
    (
      !Number.isInteger(snapshot.period) ||
      snapshot.period < 1
    )
  ) {
    throw new Error(
      "period must be null or a positive integer.",
    );
  }

  return {
    protocolVersion:
      SCOREBOARD_DEVICE_PROTOCOL_VERSION,
    commandId,
    type: "SYNC_STATE",
    snapshot: {
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      deviceId,
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
      hornActive: false,
    },
  };
}

export class GameScoreboardSyncService {
  public constructor(
    private readonly gateway:
      ScoreboardDeviceGateway,
  ) {}

  public async sync(
    snapshot: AuthoritativeGameSnapshot,
    deviceId: string,
  ): Promise<string> {
    const commandId =
      `game-sync-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2, 8)}`;

    const command =
      buildGameScoreboardSyncCommand(
        snapshot,
        deviceId,
        commandId,
      );

    await this.gateway.sendCommand(
      deviceId,
      command,
    );

    return commandId;
  }
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDevices.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("GameScoreboardSyncService")) {
  const gatewayImport = `import {
  ScoreboardDeviceGateway,
} from "../services/scoreboardDeviceGateway.js";`;

  if (!text.includes(gatewayImport)) {
    throw new Error(
      "Scoreboard gateway import anchor not found.",
    );
  }

  text = text.replace(
    gatewayImport,
`${gatewayImport}
import {
  GameScoreboardSyncService,
  type AuthoritativeGameSnapshot,
} from "../services/gameScoreboardSync.js";`,
  );
}

if (!text.includes("const syncService =")) {
  const gatewayLine =
    "const gateway = new ScoreboardDeviceGateway();";

  if (!text.includes(gatewayLine)) {
    throw new Error(
      "Scoreboard gateway instance anchor not found.",
    );
  }

  text = text.replace(
    gatewayLine,
`${gatewayLine}
const syncService =
  new GameScoreboardSyncService(gateway);`,
  );
}

if (
  !text.includes(
    '"/scoreboard-devices/:deviceId/sync-game"',
  )
) {
  const closing = text.lastIndexOf("\n}");

  if (closing < 0) {
    throw new Error(
      "Could not locate scoreboard route function closing brace.",
    );
  }

  const routeBlock = `

  app.post<{
    Params: {
      deviceId: string;
    };
    Body: AuthoritativeGameSnapshot;
  }>(
    "/scoreboard-devices/:deviceId/sync-game",
    async (request, reply) => {
      try {
        const commandId =
          await syncService.sync(
            request.body,
            request.params.deviceId,
          );

        return reply
          .code(202)
          .send({
            success: true,
            data: {
              accepted: true,
              deviceId:
                request.params.deviceId,
              gameId:
                request.body.gameId,
              commandId,
            },
          });
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "INVALID_SCOREBOARD_SYNC",
              message:
                error instanceof Error
                  ? error.message
                  : "Invalid scoreboard synchronization request.",
            },
          });
      }
    },
  );`;

  text =
    text.slice(0, closing) +
    routeBlock +
    text.slice(closing);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildGameScoreboardSyncCommand,
} from "../src/services/gameScoreboardSync.js";

describe("Milestone 10.6 game-to-scoreboard synchronization", () => {
  it("builds a full SYNC_STATE command from authoritative game state", () => {
    const command =
      buildGameScoreboardSyncCommand(
        {
          gameId: "game-1",
          homeScore: 4,
          awayScore: 3,
          period: 2,
          clock: {
            remainingMs: 88500,
            running: true,
          },
        },
        "scoreboard-1",
        "cmd-sync-game",
      );

    expect(command).toEqual({
      protocolVersion: 1,
      commandId: "cmd-sync-game",
      type: "SYNC_STATE",
      snapshot: {
        protocolVersion: 1,
        deviceId: "scoreboard-1",
        gameId: "game-1",
        homeScore: 4,
        awayScore: 3,
        period: 2,
        clock: {
          remainingMs: 88500,
          running: true,
        },
        hornActive: false,
      },
    });
  });

  it("rejects invalid authoritative scores", () => {
    expect(() =>
      buildGameScoreboardSyncCommand(
        {
          gameId: "game-1",
          homeScore: -1,
          awayScore: 0,
          period: 1,
          clock: {
            remainingMs: 1000,
            running: false,
          },
        },
        "scoreboard-1",
        "cmd-invalid",
      ),
    ).toThrow(
      "homeScore must be a non-negative integer.",
    );
  });

  it("rejects invalid clock values", () => {
    expect(() =>
      buildGameScoreboardSyncCommand(
        {
          gameId: "game-1",
          homeScore: 0,
          awayScore: 0,
          period: 1,
          clock: {
            remainingMs: -1,
            running: false,
          },
        },
        "scoreboard-1",
        "cmd-invalid-clock",
      ),
    ).toThrow(
      "remainingMs must be a non-negative number.",
    );
  });

  it("exposes the sync-game API endpoint", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/sync-game"',
    );
    expect(route).toContain(
      "GameScoreboardSyncService",
    );
    expect(route).toContain(
      "await syncService.sync",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.6 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - authoritative game -> SYNC_STATE mapper"
echo "  - GameScoreboardSyncService"
echo "  - POST /scoreboard-devices/:deviceId/sync-game"
echo "  - score / period / clock / game assignment synchronization"
echo "  - server remains authoritative"
echo "  - Milestone 10.6 tests"
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
echo "  Milestone 10.7 - Automatic Realtime Game-to-Device Sync"
