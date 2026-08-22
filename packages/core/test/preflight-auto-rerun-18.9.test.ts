import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.9 preflight auto-rerun / start-window refresh", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("enables auto-rerun by default", () => {
    expect(panel).toContain(
      "autoRerunEnabled",
    );

    expect(panel).toContain(
      "useState(true)",
    );
  });

  it("reruns when two minutes or less remain", () => {
    expect(panel).toContain(
      "remainingMs >",
    );

    expect(panel).toContain(
      "120000",
    );

    expect(panel).toContain(
      "runPreflightSilently",
    );
  });

  it("prevents overlapping background reruns", () => {
    expect(panel).toContain(
      "autoRerunInFlight",
    );
  });

  it("allows the operator to pause auto-rerun", () => {
    expect(panel).toContain(
      "Auto-Rerun:",
    );

    expect(panel).toContain(
      "Auto-rerun is paused",
    );
  });

  it("keeps server authorization authoritative", () => {
    expect(panel).toContain(
      "/game-day-hardware-preflight/",
    );
  });
});
