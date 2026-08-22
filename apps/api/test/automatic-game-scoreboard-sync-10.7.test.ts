import { describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import {
  AutomaticGameScoreboardSync,
} from "../src/services/automaticGameScoreboardSync.js";

describe("Milestone 10.7 automatic realtime game-to-device sync", () => {
  it("assigns a game to a scoreboard device", () => {
    const service =
      new AutomaticGameScoreboardSync(
        {
          sync: vi.fn(),
        } as never,
      );

    expect(
      service.assign(
        "game-1",
        "scoreboard-1",
      ),
    ).toMatchObject({
      gameId: "game-1",
      deviceId: "scoreboard-1",
    });
  });

  it("automatically syncs changed authoritative state", async () => {
    const sync = vi
      .fn()
      .mockResolvedValue("cmd-1");

    const service =
      new AutomaticGameScoreboardSync(
        { sync } as never,
      );

    service.assign(
      "game-1",
      "scoreboard-1",
    );

    const result =
      await service
        .handleAuthoritativeSnapshot({
          gameId: "game-1",
          homeScore: 2,
          awayScore: 1,
          period: 2,
          clock: {
            remainingMs: 65000,
            running: true,
          },
        });

    expect(result).toEqual({
      synced: true,
      gameId: "game-1",
      deviceId: "scoreboard-1",
      commandId: "cmd-1",
    });

    expect(sync).toHaveBeenCalledTimes(1);
  });

  it("does not resend identical state", async () => {
    const sync = vi
      .fn()
      .mockResolvedValue("cmd-1");

    const service =
      new AutomaticGameScoreboardSync(
        { sync } as never,
      );

    service.assign(
      "game-1",
      "scoreboard-1",
    );

    const snapshot = {
      gameId: "game-1",
      homeScore: 2,
      awayScore: 1,
      period: 2,
      clock: {
        remainingMs: 65000,
        running: true,
      },
    };

    await service
      .handleAuthoritativeSnapshot(
        snapshot,
      );

    const second =
      await service
        .handleAuthoritativeSnapshot(
          snapshot,
        );

    expect(second).toEqual({
      synced: false,
      gameId: "game-1",
      reason: "UNCHANGED",
    });

    expect(sync).toHaveBeenCalledTimes(1);
  });

  it("does not sync games without a device assignment", async () => {
    const service =
      new AutomaticGameScoreboardSync(
        {
          sync: vi.fn(),
        } as never,
      );

    expect(
      await service
        .handleAuthoritativeSnapshot({
          gameId: "game-unassigned",
          homeScore: 0,
          awayScore: 0,
          period: 1,
          clock: {
            remainingMs: 600000,
            running: false,
          },
        }),
    ).toEqual({
      synced: false,
      gameId: "game-unassigned",
      reason:
        "NO_DEVICE_ASSIGNED",
    });
  });

  it("exposes assignment and realtime-sync API routes", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      '"/scoreboard-devices/assignments"',
    );
    expect(route).toContain(
      '"/scoreboard-devices/assignments/:gameId"',
    );
    expect(route).toContain(
      '"/scoreboard-devices/realtime-sync"',
    );
    expect(route).toContain(
      "handleAuthoritativeSnapshot",
    );
  });
});
