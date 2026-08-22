import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.2 game-day preflight dashboard / operator workflow", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("runs preflight by game ID", () => {
    expect(panel).toContain(
      "Run Game-Day Preflight",
    );

    expect(panel).toContain(
      "/game-day-hardware-preflight/",
    );
  });

  it("shows all preflight checks", () => {
    for (const check of [
      "COMMISSIONING",
      "HEARTBEAT",
      "RELIABILITY",
      "SELF_TEST",
    ]) {
      expect(panel).toContain(
        check,
      );
    }
  });

  it("surfaces pass/fail and failure detail", () => {
    expect(panel).toContain(
      '"PASS"',
    );

    expect(panel).toContain(
      '"FAIL"',
    );

    expect(panel).toContain(
      "check.detail",
    );
  });

  it("loads latest preflight and history", () => {
    expect(panel).toContain(
      "/latest",
    );

    expect(panel).toContain(
      "/history",
    );

    expect(panel).toContain(
      "Preflight History",
    );
  });

  it("renders on scoreboard operations", () => {
    expect(page).toContain(
      "GameDayHardwarePreflightPanel",
    );

    expect(page).toContain(
      "<GameDayHardwarePreflightPanel />",
    );
  });
});
