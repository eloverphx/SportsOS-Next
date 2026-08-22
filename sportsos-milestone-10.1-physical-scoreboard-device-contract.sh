#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.1-physical-scoreboard-device-contract"
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

for required in "$ROOT/.git" "$ROOT/package.json" "$ROOT/apps"; do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CONTRACT="packages/core/src/scoreboard-device-contract.ts"
INDEX="packages/core/src/index.ts"
TEST="packages/core/test/scoreboard-device-contract-10.1.test.ts"

[[ -f "$INDEX" ]] || {
  echo "ERROR: core package index missing: $INDEX" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CONTRACT")" \
  "$BACKUP_DIR/$(dirname "$INDEX")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$CONTRACT" "$INDEX" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$CONTRACT" <<'EOF'
export const SCOREBOARD_DEVICE_PROTOCOL_VERSION = 1 as const;

export type ScoreboardDeviceConnectionState =
  | "OFFLINE"
  | "CONNECTING"
  | "ONLINE"
  | "DEGRADED";

export type ScoreboardDeviceClockState = {
  remainingMs: number;
  running: boolean;
};

export type ScoreboardDeviceSnapshot = {
  protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
  deviceId: string;
  gameId: string | null;
  connectionState: ScoreboardDeviceConnectionState;
  homeScore: number;
  awayScore: number;
  period: number | null;
  clock: ScoreboardDeviceClockState;
  hornActive: boolean;
  updatedAt: string;
};

export type ScoreboardDeviceCommand =
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_GAME";
      gameId: string | null;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_SCORE";
      homeScore: number;
      awayScore: number;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_CLOCK";
      remainingMs: number;
      running: boolean;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_PERIOD";
      period: number | null;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "HORN";
      active: boolean;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SYNC_STATE";
      snapshot: Omit<
        ScoreboardDeviceSnapshot,
        "connectionState" | "updatedAt"
      >;
    };

function assertNonNegativeInteger(
  value: number,
  label: string,
): void {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${label} must be a non-negative integer.`);
  }
}

export function validateScoreboardDeviceCommand(
  command: ScoreboardDeviceCommand,
): ScoreboardDeviceCommand {
  if (
    command.protocolVersion !==
    SCOREBOARD_DEVICE_PROTOCOL_VERSION
  ) {
    throw new Error(
      "Unsupported scoreboard device protocol version.",
    );
  }

  if (!command.commandId.trim()) {
    throw new Error("scoreboard commandId is required.");
  }

  switch (command.type) {
    case "SET_GAME":
      return command;

    case "SET_SCORE":
      assertNonNegativeInteger(command.homeScore, "homeScore");
      assertNonNegativeInteger(command.awayScore, "awayScore");
      return command;

    case "SET_CLOCK":
      if (
        !Number.isFinite(command.remainingMs) ||
        command.remainingMs < 0
      ) {
        throw new Error(
          "remainingMs must be a non-negative number.",
        );
      }
      return command;

    case "SET_PERIOD":
      if (
        command.period !== null &&
        (!Number.isInteger(command.period) || command.period < 1)
      ) {
        throw new Error(
          "period must be null or a positive integer.",
        );
      }
      return command;

    case "HORN":
      return command;

    case "SYNC_STATE":
      assertNonNegativeInteger(
        command.snapshot.homeScore,
        "homeScore",
      );
      assertNonNegativeInteger(
        command.snapshot.awayScore,
        "awayScore",
      );

      if (
        !Number.isFinite(command.snapshot.clock.remainingMs) ||
        command.snapshot.clock.remainingMs < 0
      ) {
        throw new Error(
          "remainingMs must be a non-negative number.",
        );
      }

      return command;
  }
}

export function buildScoreboardDeviceSnapshot(
  input: Omit<
    ScoreboardDeviceSnapshot,
    "protocolVersion" | "updatedAt"
  > & {
    updatedAt?: Date;
  },
): ScoreboardDeviceSnapshot {
  assertNonNegativeInteger(input.homeScore, "homeScore");
  assertNonNegativeInteger(input.awayScore, "awayScore");

  if (
    !Number.isFinite(input.clock.remainingMs) ||
    input.clock.remainingMs < 0
  ) {
    throw new Error(
      "remainingMs must be a non-negative number.",
    );
  }

  if (
    input.period !== null &&
    (!Number.isInteger(input.period) || input.period < 1)
  ) {
    throw new Error(
      "period must be null or a positive integer.",
    );
  }

  return {
    protocolVersion:
      SCOREBOARD_DEVICE_PROTOCOL_VERSION,
    deviceId: input.deviceId,
    gameId: input.gameId,
    connectionState: input.connectionState,
    homeScore: input.homeScore,
    awayScore: input.awayScore,
    period: input.period,
    clock: input.clock,
    hornActive: input.hornActive,
    updatedAt: (
      input.updatedAt ?? new Date()
    ).toISOString(),
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file = "packages/core/src/index.ts";
let text = fs.readFileSync(file, "utf8");

const exportLine =
  'export * from "./scoreboard-device-contract";';

if (!text.includes(exportLine)) {
  text = `${text.trimEnd()}\n${exportLine}\n`;
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  buildScoreboardDeviceSnapshot,
  validateScoreboardDeviceCommand,
} from "../src/scoreboard-device-contract";

describe("Milestone 10.1 physical scoreboard device contract", () => {
  it("builds a versioned device snapshot", () => {
    const snapshot = buildScoreboardDeviceSnapshot({
      deviceId: "scoreboard-1",
      gameId: "game-1",
      connectionState: "ONLINE",
      homeScore: 3,
      awayScore: 2,
      period: 2,
      clock: {
        remainingMs: 125000,
        running: true,
      },
      hornActive: false,
      updatedAt: new Date(
        "2026-08-17T12:00:00.000Z",
      ),
    });

    expect(snapshot).toMatchObject({
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      deviceId: "scoreboard-1",
      gameId: "game-1",
      homeScore: 3,
      awayScore: 2,
      period: 2,
    });
  });

  it("accepts a valid score command", () => {
    const command = validateScoreboardDeviceCommand({
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      commandId: "cmd-1",
      type: "SET_SCORE",
      homeScore: 4,
      awayScore: 1,
    });

    expect(command.type).toBe("SET_SCORE");
  });

  it("accepts a valid clock command", () => {
    expect(
      validateScoreboardDeviceCommand({
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId: "cmd-clock",
        type: "SET_CLOCK",
        remainingMs: 60000,
        running: true,
      }),
    ).toMatchObject({
      type: "SET_CLOCK",
      remainingMs: 60000,
      running: true,
    });
  });

  it("rejects negative scores", () => {
    expect(() =>
      validateScoreboardDeviceCommand({
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId: "cmd-bad-score",
        type: "SET_SCORE",
        homeScore: -1,
        awayScore: 0,
      }),
    ).toThrow(
      "homeScore must be a non-negative integer.",
    );
  });

  it("rejects invalid periods", () => {
    expect(() =>
      validateScoreboardDeviceCommand({
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId: "cmd-period",
        type: "SET_PERIOD",
        period: 0,
      }),
    ).toThrow(
      "period must be null or a positive integer.",
    );
  });

  it("supports full state synchronization", () => {
    const command = validateScoreboardDeviceCommand({
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      commandId: "cmd-sync",
      type: "SYNC_STATE",
      snapshot: {
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        deviceId: "scoreboard-1",
        gameId: "game-1",
        homeScore: 5,
        awayScore: 4,
        period: 3,
        clock: {
          remainingMs: 45000,
          running: false,
        },
        hornActive: false,
      },
    });

    expect(command.type).toBe("SYNC_STATE");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.1 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - versioned physical scoreboard protocol"
echo "  - device snapshot contract"
echo "  - SET_GAME / SET_SCORE / SET_CLOCK / SET_PERIOD"
echo "  - HORN / SYNC_STATE commands"
echo "  - command validation"
echo "  - snapshot validation"
echo "  - exported through @sportsos/core"
echo "  - Milestone 10.1 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 10.2 - MQTT Device Transport Contract"
