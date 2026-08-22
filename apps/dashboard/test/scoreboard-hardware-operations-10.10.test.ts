import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";
import {
  buildScoreboardHardwareOperationsSummary,
} from "../lib/scoreboard-hardware-operations";

describe("Milestone 10.10 scoreboard hardware operations", () => {
  it("reports no-devices when nothing has connected", () => {
    const summary =
      buildScoreboardHardwareOperationsSummary(
        [],
        [],
      );

    expect(summary.stage).toBe(
      "NO_DEVICES",
    );
    expect(
      summary.alerts.length,
    ).toBeGreaterThan(0);
  });

  it("reports ready when all discovered devices are online", () => {
    const summary =
      buildScoreboardHardwareOperationsSummary(
        [
          {
            deviceId:
              "scoreboard-1",
            state: null,
            telemetry: null,
            lastAcknowledgement:
              null,
            presence: {
              online: true,
              reportedAt:
                new Date(0).toISOString(),
            },
          },
        ],
        [],
      );

    expect(summary.stage).toBe(
      "READY",
    );
    expect(summary.online).toBe(1);
  });

  it("reports active when assignments match online device game state", () => {
    const summary =
      buildScoreboardHardwareOperationsSummary(
        [
          {
            deviceId:
              "scoreboard-1",
            state: {
              gameId: "game-1",
              homeScore: 1,
              awayScore: 0,
              period: 1,
              clock: {
                remainingMs:
                  300000,
                running: true,
              },
              hornActive: false,
              updatedAt:
                new Date(0).toISOString(),
            },
            telemetry: null,
            lastAcknowledgement:
              null,
            presence: {
              online: true,
              reportedAt:
                new Date(0).toISOString(),
            },
          },
        ],
        [
          {
            gameId: "game-1",
            deviceId:
              "scoreboard-1",
            assignedAt:
              new Date(0).toISOString(),
          },
        ],
      );

    expect(summary.stage).toBe(
      "ACTIVE",
    );
    expect(
      summary.activeGames,
    ).toBe(1);
  });

  it("renders assignment and reconcile controls", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/scoreboards/ScoreboardHardwareOperationsDashboard.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="scoreboard-hardware-operations"',
    );
    expect(component).toContain(
      "/scoreboard-devices/assignments",
    );
    expect(component).toContain(
      "/reconcile",
    );
    expect(component).toContain(
      "Reconcile Now",
    );
  });

  it("provides the scoreboard hardware operations page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Scoreboard Hardware Operations",
    );
    expect(page).toContain(
      "ScoreboardHardwareOperationsDashboard",
    );
  });
});
