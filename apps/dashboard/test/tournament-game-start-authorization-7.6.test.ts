import { describe, expect, it } from "vitest";
import {
  canAuthorizeGameStart,
  clearGameStartAuthorization,
  createGameStartAuthorization,
  readGameStartAuthorization,
  writeGameStartAuthorization,
} from "../lib/tournament-game-start-authorization";

describe("Milestone 7.6 game start authorization", () => {
  it("authorizes a normally ready game with an operator name", () => {
    expect(
      canAuthorizeGameStart({
        authorizedBy: "Scorekeeper One",
        actualReady: true,
        effectiveReady: true,
        testingOverrideEnabled: false,
      }),
    ).toBe(true);
  });

  it("does not authorize when effective readiness is blocked", () => {
    expect(
      canAuthorizeGameStart({
        authorizedBy: "Scorekeeper One",
        actualReady: false,
        effectiveReady: false,
        testingOverrideEnabled: false,
      }),
    ).toBe(false);
  });

  it("requires a reason when testing override is bypassing actual readiness", () => {
    expect(
      canAuthorizeGameStart({
        authorizedBy: "Tester",
        actualReady: false,
        effectiveReady: true,
        testingOverrideEnabled: true,
        overrideReason: "",
      }),
    ).toBe(false);

    expect(
      canAuthorizeGameStart({
        authorizedBy: "Tester",
        actualReady: false,
        effectiveReady: true,
        testingOverrideEnabled: true,
        overrideReason: "Local feature test",
      }),
    ).toBe(true);
  });

  it("creates a normal authorization snapshot", () => {
    const record = createGameStartAuthorization({
      gameId: "game-76",
      authorizedBy: "  Alex   Operator ",
      actualReady: true,
      effectiveReady: true,
      testingOverrideEnabled: false,
      now: new Date("2026-08-16T22:00:00.000Z"),
    });

    expect(record).toMatchObject({
      gameId: "game-76",
      authorizedBy: "Alex Operator",
      mode: "normal",
      actualReadyAtAuthorization: true,
      effectiveReadyAtAuthorization: true,
      overrideReason: null,
    });
  });

  it("records testing-override authorization without pretending actual readiness passed", () => {
    const record = createGameStartAuthorization({
      gameId: "game-76",
      authorizedBy: "Test Operator",
      actualReady: false,
      effectiveReady: true,
      testingOverrideEnabled: true,
      overrideReason: "Testing unfinished integrations",
      now: new Date("2026-08-16T22:00:00.000Z"),
    });

    expect(record).toMatchObject({
      mode: "testing-override",
      actualReadyAtAuthorization: false,
      effectiveReadyAtAuthorization: true,
      overrideReason: "Testing unfinished integrations",
    });
  });

  it("persists, restores, and clears an authorization", () => {
    const values = new Map<string, string>();

    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
      removeItem: (key: string) => {
        values.delete(key);
      },
    };

    const record = createGameStartAuthorization({
      gameId: "game-76",
      authorizedBy: "Operator",
      actualReady: true,
      effectiveReady: true,
      testingOverrideEnabled: false,
      now: new Date("2026-08-16T22:00:00.000Z"),
    });

    writeGameStartAuthorization(storage, record);
    expect(readGameStartAuthorization(storage, "game-76")).toEqual(record);

    clearGameStartAuthorization(storage, "game-76");
    expect(readGameStartAuthorization(storage, "game-76")).toBeNull();
  });
});
