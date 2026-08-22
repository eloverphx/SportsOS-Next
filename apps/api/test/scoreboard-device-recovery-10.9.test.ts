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
