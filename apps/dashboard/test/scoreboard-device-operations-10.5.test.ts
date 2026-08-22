import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  formatScoreboardClock,
  scoreboardDeviceHealth,
} from "../lib/scoreboard-devices";

describe("Milestone 10.5 scoreboard device operations UI", () => {
  it("formats scoreboard time", () => {
    expect(
      formatScoreboardClock(125000),
    ).toBe("2:05");
  });

  it("derives device online state", () => {
    expect(
      scoreboardDeviceHealth({
        deviceId: "scoreboard-1",
        state: null,
        telemetry: null,
        lastAcknowledgement: null,
        presence: {
          online: true,
          reportedAt:
            "2026-08-17T21:00:00.000Z",
        },
      }),
    ).toBe("ONLINE");
  });

  it("renders the device operations component", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/scoreboards/ScoreboardDeviceOperations.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="scoreboard-device-operations"',
    );
    expect(component).toContain(
      "/scoreboard-devices",
    );
    expect(component).toContain(
      "/commands",
    );
    expect(component).toContain(
      "Horn On",
    );
    expect(component).toContain(
      "Pause Clock",
    );
  });

  it("provides the scoreboard devices page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/scoreboards/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Scoreboard Devices",
    );
    expect(page).toContain(
      "ScoreboardDeviceOperations",
    );
  });
});
