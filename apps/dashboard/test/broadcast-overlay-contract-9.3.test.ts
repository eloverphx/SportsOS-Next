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
