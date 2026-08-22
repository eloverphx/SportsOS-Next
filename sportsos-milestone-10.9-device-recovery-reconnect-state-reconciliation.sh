#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.9-device-recovery-reconnect-state-reconciliation"
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
AUTO="apps/api/src/services/automaticGameScoreboardSync.ts"
BINDING="apps/api/src/services/gameScoreboardEventBinding.ts"
ROUTE="apps/api/src/routes/scoreboardDevices.ts"
RECOVERY="apps/api/src/services/scoreboardDeviceRecovery.ts"
TEST="apps/api/test/scoreboard-device-recovery-10.9.test.ts"

for file in "$GATEWAY" "$AUTO" "$BINDING" "$ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$GATEWAY")" \
  "$BACKUP_DIR/$(dirname "$AUTO")" \
  "$BACKUP_DIR/$(dirname "$RECOVERY")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$RECOVERY")" \
  "$(dirname "$TEST")"

for file in "$GATEWAY" "$AUTO" "$RECOVERY" "$ROUTE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$RECOVERY" <<'EOF'
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

    /*
     * Force a resend after reconnect by clearing the dedupe fingerprint
     * for this game before pushing the latest authoritative snapshot.
     */
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/automaticGameScoreboardSync.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("public invalidate(")) {
  const anchor = `  public getAssignment(
    gameId: string,
  ): GameScoreboardAssignment | null {`;

  if (!text.includes(anchor)) {
    throw new Error(
      "getAssignment anchor not found in AutomaticGameScoreboardSync.",
    );
  }

  const insert = `  public invalidate(
    gameId: string,
  ): void {
    this.lastFingerprint.delete(
      gameId,
    );
  }

`;

  text = text.replace(
    anchor,
    insert + anchor,
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardDeviceGateway.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type ScoreboardPresenceListener")) {
  const anchor = `export type ScoreboardDeviceRuntime = {`;

  if (!text.includes(anchor)) {
    throw new Error(
      "ScoreboardDeviceRuntime anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`export type ScoreboardPresenceListener = (
  deviceId: string,
  online: boolean,
) => void | Promise<void>;

${anchor}`,
  );
}

if (!text.includes("private readonly presenceListeners")) {
  const anchor = `  private readonly devices =
    new Map<string, ScoreboardDeviceRuntime>();`;

  if (!text.includes(anchor)) {
    throw new Error(
      "devices map anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}

  private readonly presenceListeners =
    new Set<ScoreboardPresenceListener>();`,
  );
}

if (!text.includes("public onPresence(")) {
  const anchor = `  public getDevice(
    deviceId: string,
  ): ScoreboardDeviceRuntime | null {`;

  if (!text.includes(anchor)) {
    throw new Error(
      "getDevice anchor not found.",
    );
  }

  const method = `  public onPresence(
    listener: ScoreboardPresenceListener,
  ): () => void {
    this.presenceListeners.add(
      listener,
    );

    return () => {
      this.presenceListeners.delete(
        listener,
      );
    };
  }

`;

  text = text.replace(
    anchor,
    method + anchor,
  );
}

if (!text.includes("for (const listener of this.presenceListeners)")) {
  const anchor = `      case "presence":
        device.presence =
          payload as ScoreboardMqttPresence;
        break;`;

  if (!text.includes(anchor)) {
    throw new Error(
      "presence message anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`      case "presence": {
        const presence =
          payload as ScoreboardMqttPresence;

        device.presence =
          presence;

        for (
          const listener
          of this.presenceListeners
        ) {
          void listener(
            deviceId,
            presence.online,
          );
        }

        break;
      }`,
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/gameScoreboardEventBinding.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("rememberAuthoritativeSnapshot")) {
  const importAnchor = `import {
  AutomaticGameScoreboardSync,
} from "./automaticGameScoreboardSync.js";`;

  if (!text.includes(importAnchor)) {
    throw new Error(
      "AutomaticGameScoreboardSync import anchor missing.",
    );
  }

  text = text.replace(
    importAnchor,
`${importAnchor}
import type {
  ScoreboardDeviceRecoveryService,
} from "./scoreboardDeviceRecovery.js";`,
  );

  const variableAnchor = `let automaticSync:
  AutomaticGameScoreboardSync | null = null;`;

  if (!text.includes(variableAnchor)) {
    throw new Error(
      "automaticSync binding variable missing.",
    );
  }

  text = text.replace(
    variableAnchor,
`${variableAnchor}

let recoveryService:
  ScoreboardDeviceRecoveryService | null = null;`,
  );

  const bindAnchor = `export function bindAutomaticGameScoreboardSync(
  service: AutomaticGameScoreboardSync,
): void {
  automaticSync = service;
}`;

  if (!text.includes(bindAnchor)) {
    throw new Error(
      "bindAutomaticGameScoreboardSync anchor missing.",
    );
  }

  text = text.replace(
    bindAnchor,
`${bindAnchor}

export function bindScoreboardDeviceRecovery(
  service: ScoreboardDeviceRecoveryService,
): void {
  recoveryService = service;
}`,
  );

  const notifyAnchor = `  await automaticSync
    .handleAuthoritativeSnapshot(
      snapshot,
    );`;

  if (!text.includes(notifyAnchor)) {
    throw new Error(
      "automatic snapshot notification anchor missing.",
    );
  }

  text = text.replace(
    notifyAnchor,
`  recoveryService
    ?.rememberAuthoritativeSnapshot(
      snapshot,
    );

${notifyAnchor}`,
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDevices.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("ScoreboardDeviceRecoveryService")) {
  const anchor = `import {
  bindAutomaticGameScoreboardSync,
} from "../services/gameScoreboardEventBinding.js";`;

  if (!text.includes(anchor)) {
    throw new Error(
      "gameScoreboardEventBinding import anchor missing.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}
import {
  bindScoreboardDeviceRecovery,
} from "../services/gameScoreboardEventBinding.js";
import {
  ScoreboardDeviceRecoveryService,
} from "../services/scoreboardDeviceRecovery.js";`,
  );
}

if (!text.includes("const recoveryService =")) {
  const anchor = `const automaticSync =
  new AutomaticGameScoreboardSync(syncService);
bindAutomaticGameScoreboardSync(automaticSync);`;

  if (!text.includes(anchor)) {
    throw new Error(
      "automaticSync initialization anchor missing.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}
const recoveryService =
  new ScoreboardDeviceRecoveryService(
    automaticSync,
  );
bindScoreboardDeviceRecovery(
  recoveryService,
);

gateway.onPresence(
  async (deviceId, online) => {
    if (!online) {
      return;
    }

    await recoveryService
      .reconcileDevice(
        deviceId,
      );
  },
);`,
  );
}

if (
  !text.includes(
    '"/scoreboard-devices/:deviceId/reconcile"',
  )
) {
  const closing = text.lastIndexOf("\n}");

  if (closing < 0) {
    throw new Error(
      "scoreboard routes closing brace not found.",
    );
  }

  const block = `

  app.post<{
    Params: {
      deviceId: string;
    };
  }>(
    "/scoreboard-devices/:deviceId/reconcile",
    async (request, reply) => {
      const result =
        await recoveryService
          .reconcileDevice(
            request.params.deviceId,
          );

      return reply.send({
        success: true,
        data: {
          result,
        },
      });
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
import {
  describe,
  expect,
  it,
  vi,
} from "vitest";
import fs from "node:fs";
import {
  ScoreboardDeviceRecoveryService,
} from "../src/services/scoreboardDeviceRecovery.js";

describe("Milestone 10.9 scoreboard reconnect recovery", () => {
  it("reconciles a reconnecting assigned device to the latest authoritative state", async () => {
    const handleAuthoritativeSnapshot =
      vi.fn().mockResolvedValue({
        synced: true,
        gameId: "game-1",
        deviceId: "scoreboard-1",
        commandId: "cmd-recover",
      });

    const invalidate =
      vi.fn();

    const service =
      new ScoreboardDeviceRecoveryService(
        {
          listAssignments: () => [
            {
              gameId: "game-1",
              deviceId:
                "scoreboard-1",
              assignedAt:
                new Date(0).toISOString(),
            },
          ],
          invalidate,
          handleAuthoritativeSnapshot,
        } as never,
      );

    service.rememberAuthoritativeSnapshot({
      gameId: "game-1",
      homeScore: 3,
      awayScore: 2,
      period: 2,
      clock: {
        remainingMs: 54000,
        running: true,
      },
    });

    const result =
      await service.reconcileDevice(
        "scoreboard-1",
      );

    expect(invalidate).toHaveBeenCalledWith(
      "game-1",
    );

    expect(
      handleAuthoritativeSnapshot,
    ).toHaveBeenCalledTimes(1);

    expect(result).toEqual({
      reconciled: true,
      deviceId: "scoreboard-1",
      gameId: "game-1",
      commandId: "cmd-recover",
    });
  });

  it("does nothing when the device has no assigned game", async () => {
    const service =
      new ScoreboardDeviceRecoveryService(
        {
          listAssignments: () => [],
        } as never,
      );

    expect(
      await service.reconcileDevice(
        "scoreboard-unknown",
      ),
    ).toEqual({
      reconciled: false,
      deviceId:
        "scoreboard-unknown",
      reason: "NO_ASSIGNED_GAME",
    });
  });

  it("does not invent state when no authoritative snapshot has been observed", async () => {
    const service =
      new ScoreboardDeviceRecoveryService(
        {
          listAssignments: () => [
            {
              gameId: "game-1",
              deviceId:
                "scoreboard-1",
              assignedAt:
                new Date(0).toISOString(),
            },
          ],
        } as never,
      );

    expect(
      await service.reconcileDevice(
        "scoreboard-1",
      ),
    ).toEqual({
      reconciled: false,
      deviceId: "scoreboard-1",
      reason:
        "NO_AUTHORITATIVE_SNAPSHOT",
    });
  });

  it("wires presence recovery and a manual reconcile endpoint", () => {
    const gateway = fs.readFileSync(
      new URL(
        "../src/services/scoreboardDeviceGateway.ts",
        import.meta.url,
      ),
      "utf8",
    );

    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(gateway).toContain(
      "public onPresence",
    );

    expect(route).toContain(
      "gateway.onPresence",
    );

    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/reconcile"',
    );
  });

  it("remembers authoritative snapshots from the realtime binding", () => {
    const binding = fs.readFileSync(
      new URL(
        "../src/services/gameScoreboardEventBinding.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(binding).toContain(
      "rememberAuthoritativeSnapshot",
    );
    expect(binding).toContain(
      "bindScoreboardDeviceRecovery",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.9 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - authoritative snapshot cache for assigned games"
echo "  - device presence listener support in MQTT gateway"
echo "  - automatic reconciliation when a device comes online"
echo "  - dedupe invalidation so reconnect always forces a fresh sync"
echo "  - manual POST /scoreboard-devices/:deviceId/reconcile fallback"
echo "  - no state invention when authoritative snapshot is unavailable"
echo "  - Milestone 10.9 tests"
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
echo "  Milestone 10.10 - Scoreboard Hardware Operations Dashboard / Milestone 10 Closeout"
