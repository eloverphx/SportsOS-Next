#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.9-device-recovery-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

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
  "$BACKUP_DIR/$(dirname "$BINDING")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$RECOVERY")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$RECOVERY")" \
  "$(dirname "$TEST")"

for file in "$GATEWAY" "$AUTO" "$BINDING" "$ROUTE" "$RECOVERY" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

# Ensure recovery service exists. This is safe if the failed installer already wrote it.
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

# Ensure AutomaticGameScoreboardSync has invalidate(), using a structural class insertion.
node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/services/automaticGameScoreboardSync.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("public invalidate(")) {
  const classIndex =
    text.indexOf("export class AutomaticGameScoreboardSync");

  if (classIndex < 0) {
    throw new Error(
      "AutomaticGameScoreboardSync class not found.",
    );
  }

  const methodCandidates = [
    "  public getAssignment(",
    "  public listAssignments(",
    "  public async handleAuthoritativeSnapshot(",
  ];

  let insertAt = -1;

  for (const marker of methodCandidates) {
    const idx = text.indexOf(marker, classIndex);
    if (idx >= 0) {
      insertAt = idx;
      break;
    }
  }

  if (insertAt < 0) {
    throw new Error(
      "Could not find a safe method insertion point in AutomaticGameScoreboardSync.",
    );
  }

  const method = `  public invalidate(
    gameId: string,
  ): void {
    this.lastFingerprint.delete(
      gameId,
    );
  }

`;

  text =
    text.slice(0, insertAt) +
    method +
    text.slice(insertAt);
}

fs.writeFileSync(file, text);
NODE

# Patch the gateway structurally rather than relying on getDevice formatting.
node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/services/scoreboardDeviceGateway.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type ScoreboardPresenceListener")) {
  const classMarker =
    "export class ScoreboardDeviceGateway";

  const classIndex =
    text.indexOf(classMarker);

  if (classIndex < 0) {
    throw new Error(
      "ScoreboardDeviceGateway class not found.",
    );
  }

  const typeBlock = `export type ScoreboardPresenceListener = (
  deviceId: string,
  online: boolean,
) => void | Promise<void>;

`;

  text =
    text.slice(0, classIndex) +
    typeBlock +
    text.slice(classIndex);
}

if (!text.includes("presenceListeners")) {
  const classBrace =
    text.indexOf(
      "{",
      text.indexOf(
        "export class ScoreboardDeviceGateway",
      ),
    );

  if (classBrace < 0) {
    throw new Error(
      "ScoreboardDeviceGateway class body not found.",
    );
  }

  const property = `
  private readonly presenceListeners =
    new Set<ScoreboardPresenceListener>();
`;

  text =
    text.slice(0, classBrace + 1) +
    property +
    text.slice(classBrace + 1);
}

if (!text.includes("public onPresence(")) {
  const insertionMarkers = [
    "  public listDevices(",
    "  public async sendCommand(",
    "  private ensureDevice(",
    "  private handleMessage(",
  ];

  let insertAt = -1;

  for (const marker of insertionMarkers) {
    const idx = text.indexOf(marker);
    if (idx >= 0) {
      insertAt = idx;
      break;
    }
  }

  if (insertAt < 0) {
    throw new Error(
      "Could not find a safe method insertion point in ScoreboardDeviceGateway.",
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

  text =
    text.slice(0, insertAt) +
    method +
    text.slice(insertAt);
}

if (!text.includes("for (const listener of this.presenceListeners)")) {
  const caseRegex =
    /case\s+"presence"\s*:\s*(?:\{)?[\s\S]*?device\.presence\s*=\s*payload\s+as\s+ScoreboardMqttPresence\s*;[\s\S]*?break\s*;(?:\s*\})?/m;

  const match = text.match(caseRegex);

  if (!match) {
    throw new Error(
      "Could not locate the gateway presence handler structurally.",
    );
  }

  const replacement = `case "presence": {
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
      }`;

  text =
    text.slice(0, match.index) +
    replacement +
    text.slice(
      match.index + match[0].length,
    );
}

fs.writeFileSync(file, text);
NODE

# Bind recovery into the authoritative game update service, idempotently.
node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/services/gameScoreboardEventBinding.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("ScoreboardDeviceRecoveryService")) {
  const importAnchor =
    'import {\n  AutomaticGameScoreboardSync,\n} from "./automaticGameScoreboardSync.js";';

  if (!text.includes(importAnchor)) {
    throw new Error(
      "AutomaticGameScoreboardSync import not found.",
    );
  }

  text = text.replace(
    importAnchor,
`${importAnchor}
import type {
  ScoreboardDeviceRecoveryService,
} from "./scoreboardDeviceRecovery.js";`,
  );
}

if (!text.includes("let recoveryService:")) {
  const automaticDecl =
    /let\s+automaticSync\s*:\s*AutomaticGameScoreboardSync\s*\|\s*null\s*=\s*null\s*;/;

  const match =
    text.match(automaticDecl);

  if (!match) {
    throw new Error(
      "automaticSync binding declaration not found.",
    );
  }

  text = text.replace(
    automaticDecl,
`${match[0]}

let recoveryService:
  ScoreboardDeviceRecoveryService | null = null;`,
  );
}

if (!text.includes("bindScoreboardDeviceRecovery")) {
  const bindRegex =
    /export function bindAutomaticGameScoreboardSync\([\s\S]*?\n\}/m;

  const match =
    text.match(bindRegex);

  if (!match) {
    throw new Error(
      "bindAutomaticGameScoreboardSync function not found.",
    );
  }

  text = text.replace(
    bindRegex,
`${match[0]}

export function bindScoreboardDeviceRecovery(
  service: ScoreboardDeviceRecoveryService,
): void {
  recoveryService = service;
}`,
  );
}

if (!text.includes("rememberAuthoritativeSnapshot(")) {
  const syncCall =
    /await\s+automaticSync[\s\S]*?\.handleAuthoritativeSnapshot\(\s*snapshot\s*,?\s*\)\s*;/m;

  const match =
    text.match(syncCall);

  if (!match) {
    throw new Error(
      "Automatic scoreboard snapshot call not found.",
    );
  }

  text = text.replace(
    syncCall,
`recoveryService
    ?.rememberAuthoritativeSnapshot(
      snapshot,
    );

  ${match[0]}`,
  );
}

fs.writeFileSync(file, text);
NODE

# Wire recovery service + presence callback into scoreboard routes.
node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardDevices.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("ScoreboardDeviceRecoveryService")) {
  const importMarker =
    'from "../services/gameScoreboardEventBinding.js";';

  const idx =
    text.indexOf(importMarker);

  if (idx < 0) {
    throw new Error(
      "gameScoreboardEventBinding import not found.",
    );
  }

  const statementStart =
    text.lastIndexOf(
      "import",
      idx,
    );
  const statementEnd =
    text.indexOf(
      ";",
      idx,
    ) + 1;

  const current =
    text.slice(
      statementStart,
      statementEnd,
    );

  let replacement = current;

  if (
    !replacement.includes(
      "bindScoreboardDeviceRecovery",
    )
  ) {
    replacement =
      replacement.replace(
        "bindAutomaticGameScoreboardSync,",
        `bindAutomaticGameScoreboardSync,
  bindScoreboardDeviceRecovery,`,
      );
  }

  replacement += `
import {
  ScoreboardDeviceRecoveryService,
} from "../services/scoreboardDeviceRecovery.js";`;

  text =
    text.slice(0, statementStart) +
    replacement +
    text.slice(statementEnd);
}

if (!text.includes("const recoveryService =")) {
  const automaticRegex =
    /const\s+automaticSync\s*=\s*new\s+AutomaticGameScoreboardSync\(\s*syncService\s*,?\s*\)\s*;/m;

  const match =
    text.match(automaticRegex);

  if (!match) {
    throw new Error(
      "automaticSync initialization not found.",
    );
  }

  const insert = `${match[0]}
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
);`;

  text = text.replace(
    automaticRegex,
    insert,
  );
}

if (
  !text.includes(
    '"/scoreboard-devices/:deviceId/reconcile"',
  )
) {
  const functionEnd =
    text.lastIndexOf("\n}");

  if (functionEnd < 0) {
    throw new Error(
      "scoreboardDevicesRoutes closing brace not found.",
    );
  }

  const routeBlock = `

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
    text.slice(0, functionEnd) +
    routeBlock +
    text.slice(functionEnd);
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
  it("forces the latest authoritative state to a reconnecting assigned device", async () => {
    const invalidate = vi.fn();
    const handleAuthoritativeSnapshot =
      vi.fn().mockResolvedValue({
        synced: true,
        gameId: "game-1",
        deviceId: "scoreboard-1",
        commandId: "cmd-recover",
      });

    const service =
      new ScoreboardDeviceRecoveryService(
        {
          listAssignments: () => [
            {
              gameId: "game-1",
              deviceId: "scoreboard-1",
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

  it("does not invent state for an unassigned device", async () => {
    const service =
      new ScoreboardDeviceRecoveryService(
        {
          listAssignments: () => [],
        } as never,
      );

    expect(
      await service.reconcileDevice(
        "scoreboard-x",
      ),
    ).toEqual({
      reconciled: false,
      deviceId: "scoreboard-x",
      reason: "NO_ASSIGNED_GAME",
    });
  });

  it("requires an observed authoritative snapshot", async () => {
    const service =
      new ScoreboardDeviceRecoveryService(
        {
          listAssignments: () => [
            {
              gameId: "game-1",
              deviceId: "scoreboard-1",
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

  it("wires presence recovery into the MQTT gateway and routes", () => {
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
    expect(gateway).toContain(
      "presenceListeners",
    );
    expect(route).toContain(
      "gateway.onPresence",
    );
    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/reconcile"',
    );
  });

  it("remembers authoritative snapshots in the realtime binding", () => {
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
echo " SportsOS-Next Milestone 10.9 repair installed"
echo "============================================================"
echo
echo "Recovered from partial 10.9 installation:"
echo "  - preserves/recreates recovery service"
echo "  - preserves/adds automatic-sync invalidate()"
echo "  - structurally patches gateway presence listeners"
echo "  - binds latest authoritative snapshot cache"
echo "  - auto-reconciles devices on ONLINE presence"
echo "  - adds manual reconcile endpoint"
echo "  - adds Milestone 10.9 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
