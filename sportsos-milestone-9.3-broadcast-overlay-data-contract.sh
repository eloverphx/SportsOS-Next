#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="9.3-broadcast-overlay-data-contract"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

LIB="apps/dashboard/lib/broadcast-overlay-contract.ts"
ROUTE="apps/dashboard/app/api/tournament/broadcast/overlay/[gameId]/route.ts"
TEST="apps/dashboard/test/broadcast-overlay-contract-9.3.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$LIB")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$ROUTE")"

for file in "$LIB" "$ROUTE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$LIB" <<'EOF'
export type BroadcastOverlayTeam = {
  id: string;
  name: string;
  shortName: string | null;
  logoUrl: string | null;
  score: number;
};

export type BroadcastOverlayClock = {
  remainingMs: number;
  running: boolean;
};

export type BroadcastOverlayPowerPlay = {
  teamId: string;
  remainingMs: number;
} | null;

export type BroadcastOverlaySnapshot = {
  version: 1;
  generatedAt: string;
  gameId: string;
  status: string;
  phase: string | null;
  period: number | null;
  home: BroadcastOverlayTeam;
  away: BroadcastOverlayTeam;
  clock: BroadcastOverlayClock;
  powerPlay: BroadcastOverlayPowerPlay;
};

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord | null {
  return value && typeof value === "object"
    ? (value as UnknownRecord)
    : null;
}

function stringValue(
  value: unknown,
  fallback = "",
): string {
  return typeof value === "string" ? value : fallback;
}

function nullableString(
  value: unknown,
): string | null {
  return typeof value === "string" && value.trim()
    ? value
    : null;
}

function numberValue(
  value: unknown,
  fallback = 0,
): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function nullableNumber(
  value: unknown,
): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : null;
}

function booleanValue(
  value: unknown,
  fallback = false,
): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function teamSnapshot(
  teamValue: unknown,
  fallbackId: unknown,
  fallbackName: unknown,
  fallbackScore: unknown,
): BroadcastOverlayTeam {
  const team = record(teamValue);

  return {
    id:
      stringValue(team?.id) ||
      stringValue(fallbackId),
    name:
      stringValue(team?.name) ||
      stringValue(fallbackName) ||
      "Unknown",
    shortName:
      nullableString(team?.shortName) ??
      nullableString(team?.abbreviation),
    logoUrl:
      nullableString(team?.logoUrl) ??
      nullableString(team?.logo),
    score: numberValue(fallbackScore),
  };
}

export function normalizeBroadcastOverlaySnapshot(
  gameValue: unknown,
  generatedAt = new Date(),
): BroadcastOverlaySnapshot {
  const game = record(gameValue);

  if (!game) {
    throw new Error(
      "Broadcast overlay game payload must be an object.",
    );
  }

  const gameId = stringValue(game.id);

  if (!gameId) {
    throw new Error(
      "Broadcast overlay game payload is missing id.",
    );
  }

  const remainingMs =
    nullableNumber(game.remainingMs) ??
    nullableNumber(game.clockRemainingMs) ??
    nullableNumber(record(game.clock)?.remainingMs) ??
    0;

  const running =
    booleanValue(game.isClockRunning) ||
    booleanValue(game.clockRunning) ||
    booleanValue(record(game.clock)?.running);

  const powerPlayRecord =
    record(game.powerPlay) ??
    record(game.activePowerPlay);

  const powerPlayTeamId =
    stringValue(powerPlayRecord?.teamId);

  const powerPlayRemainingMs =
    nullableNumber(powerPlayRecord?.remainingMs);

  return {
    version: 1,
    generatedAt: generatedAt.toISOString(),
    gameId,
    status: stringValue(game.status, "UNKNOWN"),
    phase:
      nullableString(game.gamePhase) ??
      nullableString(game.phase),
    period:
      nullableNumber(game.period) ??
      nullableNumber(game.currentPeriod),
    home: teamSnapshot(
      game.homeTeam,
      game.homeTeamId,
      game.homeTeamName,
      game.homeScore,
    ),
    away: teamSnapshot(
      game.awayTeam,
      game.awayTeamId,
      game.awayTeamName,
      game.awayScore,
    ),
    clock: {
      remainingMs: Math.max(0, remainingMs),
      running,
    },
    powerPlay:
      powerPlayTeamId &&
      powerPlayRemainingMs !== null
        ? {
            teamId: powerPlayTeamId,
            remainingMs: Math.max(
              0,
              powerPlayRemainingMs,
            ),
          }
        : null,
  };
}
EOF

cat > "$ROUTE" <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import {
  normalizeBroadcastOverlaySnapshot,
} from "../../../../../../lib/broadcast-overlay-contract";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

export async function GET(
  request: NextRequest,
  context: {
    params: Promise<{
      gameId: string;
    }>;
  },
) {
  const { gameId } = await context.params;

  const response = await fetch(
    `${API_BASE_URL}/games/${encodeURIComponent(gameId)}`,
    {
      cache: "no-store",
      headers: {
        accept: "application/json",
        ...(request.headers.get("authorization")
          ? {
              authorization:
                request.headers.get("authorization") ?? "",
            }
          : {}),
        ...(request.headers.get("cookie")
          ? {
              cookie:
                request.headers.get("cookie") ?? "",
            }
          : {}),
      },
    },
  );

  if (!response.ok) {
    return NextResponse.json(
      {
        error: "Unable to load authoritative game for overlay.",
        upstreamStatus: response.status,
      },
      {
        status: response.status === 404 ? 404 : 502,
      },
    );
  }

  const payload = (await response.json()) as unknown;

  const game =
    payload &&
    typeof payload === "object" &&
    "game" in payload
      ? (payload as { game: unknown }).game
      : payload;

  try {
    return NextResponse.json(
      normalizeBroadcastOverlaySnapshot(game),
      {
        headers: {
          "cache-control": "no-store",
        },
      },
    );
  } catch (cause) {
    return NextResponse.json(
      {
        error:
          cause instanceof Error
            ? cause.message
            : "Unable to normalize broadcast overlay payload.",
      },
      {
        status: 500,
      },
    );
  }
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  normalizeBroadcastOverlaySnapshot,
} from "../lib/broadcast-overlay-contract";

describe("Milestone 9.3 broadcast overlay data contract", () => {
  it("normalizes authoritative game data into overlay version 1", () => {
    const snapshot =
      normalizeBroadcastOverlaySnapshot(
        {
          id: "game-93",
          status: "LIVE",
          gamePhase: "REGULATION",
          period: 2,
          homeTeamId: "home",
          awayTeamId: "away",
          homeTeamName: "Lakers",
          awayTeamName: "Bears",
          homeScore: 3,
          awayScore: 2,
          remainingMs: 125000,
          isClockRunning: true,
        },
        new Date("2026-08-17T03:30:00.000Z"),
      );

    expect(snapshot).toMatchObject({
      version: 1,
      gameId: "game-93",
      status: "LIVE",
      phase: "REGULATION",
      period: 2,
      home: {
        id: "home",
        name: "Lakers",
        score: 3,
      },
      away: {
        id: "away",
        name: "Bears",
        score: 2,
      },
      clock: {
        remainingMs: 125000,
        running: true,
      },
    });
  });

  it("uses nested team metadata when available", () => {
    const snapshot =
      normalizeBroadcastOverlaySnapshot({
        id: "game-team-metadata",
        homeTeam: {
          id: "a",
          name: "Lakers",
          shortName: "PL",
          logoUrl: "/logos/lakers.png",
        },
        awayTeam: {
          id: "b",
          name: "Bears",
          abbreviation: "BR",
          logo: "/logos/bears.png",
        },
        homeScore: 1,
        awayScore: 0,
      });

    expect(snapshot.home).toMatchObject({
      id: "a",
      name: "Lakers",
      shortName: "PL",
      logoUrl: "/logos/lakers.png",
    });

    expect(snapshot.away).toMatchObject({
      id: "b",
      name: "Bears",
      shortName: "BR",
      logoUrl: "/logos/bears.png",
    });
  });

  it("normalizes active power play metadata", () => {
    const snapshot =
      normalizeBroadcastOverlaySnapshot({
        id: "game-pp",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 0,
        awayScore: 0,
        activePowerPlay: {
          teamId: "a",
          remainingMs: 83000,
        },
      });

    expect(snapshot.powerPlay).toEqual({
      teamId: "a",
      remainingMs: 83000,
    });
  });

  it("clamps negative clock values to zero", () => {
    const snapshot =
      normalizeBroadcastOverlaySnapshot({
        id: "game-clock",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 0,
        awayScore: 0,
        remainingMs: -100,
      });

    expect(snapshot.clock.remainingMs).toBe(0);
  });

  it("rejects payloads without a game id", () => {
    expect(() =>
      normalizeBroadcastOverlaySnapshot({
        homeScore: 1,
        awayScore: 2,
      }),
    ).toThrow(
      "Broadcast overlay game payload is missing id.",
    );
  });

  it("provides a per-game overlay API route", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/broadcast/overlay/[gameId]/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "normalizeBroadcastOverlaySnapshot",
    );
    expect(route).toContain(
      "/games/${encodeURIComponent(gameId)}",
    );
    expect(route).toContain(
      '"cache-control": "no-store"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - versioned broadcast overlay contract"
echo "  - authoritative per-game overlay snapshot"
echo "  - teams / logos / scores"
echo "  - period / phase / clock"
echo "  - optional power-play metadata"
echo "  - GET /api/tournament/broadcast/overlay/:gameId"
echo "  - no-store cache behavior"
echo "  - Milestone 9.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.4 - Browser Source Overlay"
