#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="9.1-broadcast-session-state"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

LIB="apps/dashboard/lib/tournament-broadcast-session.ts"
TEST="apps/dashboard/test/tournament-broadcast-session-9.1.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

for file in "$LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$LIB" <<'EOF'
export type BroadcastTransportState =
  | "OFFLINE"
  | "CONNECTING"
  | "READY"
  | "LIVE"
  | "ERROR";

export type BroadcastOverlayState =
  | "DISABLED"
  | "READY"
  | "ACTIVE";

export type BroadcastSessionInput = {
  gameId: string;
  operatorAssigned: boolean;
  gameAuthorized: boolean;
  gameLive: boolean;
  transportState: BroadcastTransportState;
  overlayState: BroadcastOverlayState;
  streamKeyConfigured: boolean;
};

export type BroadcastSessionStatus =
  | "NOT_READY"
  | "READY"
  | "LIVE"
  | "DEGRADED";

export type BroadcastSessionSummary = {
  gameId: string;
  status: BroadcastSessionStatus;
  ready: boolean;
  canGoLive: boolean;
  overlayEligible: boolean;
  blockers: string[];
  warnings: string[];
};

export function buildBroadcastSessionSummary(
  input: BroadcastSessionInput,
): BroadcastSessionSummary {
  const blockers: string[] = [];
  const warnings: string[] = [];

  if (!input.operatorAssigned) {
    blockers.push("Broadcast operator is not assigned.");
  }

  if (!input.gameAuthorized) {
    blockers.push("Game start is not authorized.");
  }

  if (!input.streamKeyConfigured) {
    blockers.push("Stream destination is not configured.");
  }

  if (
    input.transportState === "OFFLINE" ||
    input.transportState === "ERROR"
  ) {
    blockers.push("Broadcast transport is not ready.");
  }

  if (input.overlayState === "DISABLED") {
    warnings.push("Broadcast overlay is disabled.");
  }

  if (
    input.gameLive &&
    input.transportState !== "LIVE"
  ) {
    warnings.push(
      "Game is live but broadcast transport is not live.",
    );
  }

  if (
    input.transportState === "LIVE" &&
    !input.gameLive
  ) {
    warnings.push(
      "Broadcast transport is live before the game is live.",
    );
  }

  const ready =
    blockers.length === 0 &&
    (
      input.transportState === "READY" ||
      input.transportState === "LIVE"
    );

  const canGoLive =
    ready &&
    input.transportState === "READY" &&
    !input.gameLive;

  const overlayEligible =
    input.overlayState !== "DISABLED" &&
    input.gameAuthorized;

  let status: BroadcastSessionStatus = "NOT_READY";

  if (
    input.transportState === "LIVE" &&
    input.gameLive &&
    blockers.length === 0
  ) {
    status =
      warnings.length > 0 ? "DEGRADED" : "LIVE";
  } else if (
    ready &&
    warnings.length === 0
  ) {
    status = "READY";
  } else if (
    ready ||
    (
      input.gameLive &&
      warnings.length > 0
    )
  ) {
    status = "DEGRADED";
  }

  return {
    gameId: input.gameId,
    status,
    ready,
    canGoLive,
    overlayEligible,
    blockers,
    warnings,
  };
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  buildBroadcastSessionSummary,
} from "../lib/tournament-broadcast-session";

describe("Milestone 9.1 broadcast session state", () => {
  it("reports ready when all broadcast prerequisites are satisfied", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-1",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "READY",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("READY");
    expect(summary.ready).toBe(true);
    expect(summary.canGoLive).toBe(true);
    expect(summary.blockers).toEqual([]);
  });

  it("blocks when no operator is assigned", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-2",
      operatorAssigned: false,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "READY",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("NOT_READY");
    expect(summary.blockers).toContain(
      "Broadcast operator is not assigned.",
    );
  });

  it("blocks when the stream destination is not configured", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-3",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "READY",
      streamKeyConfigured: false,
    });

    expect(summary.ready).toBe(false);
    expect(summary.blockers).toContain(
      "Stream destination is not configured.",
    );
  });

  it("reports live when game and transport are both live", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-4",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: true,
      transportState: "LIVE",
      overlayState: "ACTIVE",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("LIVE");
    expect(summary.ready).toBe(true);
    expect(summary.canGoLive).toBe(false);
  });

  it("reports degraded when the game is live but transport is not", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-5",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: true,
      transportState: "READY",
      overlayState: "ACTIVE",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("DEGRADED");
    expect(summary.warnings).toContain(
      "Game is live but broadcast transport is not live.",
    );
  });

  it("warns when transport is live before the game", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-6",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "LIVE",
      overlayState: "READY",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("DEGRADED");
    expect(summary.warnings).toContain(
      "Broadcast transport is live before the game is live.",
    );
  });

  it("keeps overlay eligibility separate from transport readiness", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-7",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "DISABLED",
      streamKeyConfigured: true,
    });

    expect(summary.overlayEligible).toBe(false);
    expect(summary.warnings).toContain(
      "Broadcast overlay is disabled.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - pure broadcast session state model"
echo "  - transport states: OFFLINE / CONNECTING / READY / LIVE / ERROR"
echo "  - overlay states: DISABLED / READY / ACTIVE"
echo "  - readiness blockers"
echo "  - degraded-state warnings"
echo "  - go-live eligibility"
echo "  - overlay eligibility"
echo "  - Milestone 9.1 unit tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.2 - Broadcast Session API / Operator UI"
