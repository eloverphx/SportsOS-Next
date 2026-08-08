import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("game event transaction lock order", () => {
  it("locks the game before the event and idempotency ledger when voiding", () => {
    const repository = fs.readFileSync(
      new URL("../src/modules/game-events/repository.ts", import.meta.url),
      "utf8",
    );

    const voidStart = repository.indexOf("export async function voidGameEvent");
    expect(voidStart).toBeGreaterThanOrEqual(0);

    const body = repository.slice(voidStart);
    const gameLock = body.indexOf(
      '"SELECT home_score, away_score FROM games WHERE id = ? FOR UPDATE"',
    );
    const eventLock = body.indexOf(
      '"SELECT * FROM game_events WHERE id = ? AND game_id = ? FOR UPDATE"',
    );
    const ledgerLock = body.indexOf("FROM game_action_requests");

    expect(gameLock).toBeGreaterThanOrEqual(0);
    expect(eventLock).toBeGreaterThan(gameLock);
    expect(ledgerLock).toBeGreaterThan(eventLock);
  });

  it("keeps create-event transactions game-first as well", () => {
    const repository = fs.readFileSync(
      new URL("../src/modules/game-events/repository.ts", import.meta.url),
      "utf8",
    );

    const createStart = repository.indexOf("export async function createGameEvent");
    const voidStart = repository.indexOf("export async function voidGameEvent");
    const body = repository.slice(createStart, voidStart);

    const gameLock = body.indexOf("SELECT * FROM games WHERE id = ? FOR UPDATE");
    const ledgerLock = body.indexOf("FROM game_action_requests");

    expect(gameLock).toBeGreaterThanOrEqual(0);
    expect(ledgerLock).toBeGreaterThan(gameLock);
  });
});
