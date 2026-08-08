import fs from "node:fs";
import { describe, expect, it } from "vitest";
import type {
  BroadcastSoundPayload,
  GameScoredPayload,
  RealtimeOutboxEvent,
  RealtimeServerEvents,
} from "@sportsos/core";

describe("typed realtime contracts", () => {
  it("keeps transactional outbox events tied to shared payload contracts", () => {
    const scored: GameScoredPayload = {
      id: 42,
      gameId: 42,
      organizationId: 7,
      action: { action: "adjustScore", side: "home", amount: 1 },
      replayed: false,
      homeScore: 2,
      awayScore: 1,
      period: 2,
      clockRemainingMs: 600000,
      clockRunning: true,
      status: "LIVE",
      gamePhase: "REGULATION",
    };

    const event: RealtimeOutboxEvent = {
      event: "game:scored",
      room: "game:42",
      payload: scored,
    };

    const sound: BroadcastSoundPayload = {
      gameId: 42,
      soundId: "goal-42",
      type: "GOAL",
    };

    const listener: RealtimeServerEvents["scoreboard:sound"] = (payload) => {
      expect(payload.soundId).toBe("goal-42");
    };

    listener(sound);
    expect(event.event).toBe("game:scored");
  });

  it("uses the shared outbox event union instead of string plus unknown", () => {
    const source = fs.readFileSync(
      new URL("../src/infrastructure/realtime-outbox.ts", import.meta.url),
      "utf8",
    );

    expect(source).toContain('RealtimeOutboxEvent } from "@sportsos/core"');
    expect(source).not.toContain("readonly event: string");
    expect(source).not.toContain("readonly payload: unknown");
  });
});
