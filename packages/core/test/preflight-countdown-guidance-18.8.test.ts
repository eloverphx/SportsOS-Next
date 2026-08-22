import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.8 preflight countdown / start-window guidance", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("updates the countdown every second", () => {
    expect(panel).toContain(
      "Preflight countdown clock",
    );

    expect(panel).toContain(
      "setInterval",
    );

    expect(panel).toContain(
      "1000",
    );
  });

  it("calculates remaining freshness from server expiration", () => {
    expect(panel).toContain(
      "remainingFreshnessMs",
    );

    expect(panel).toContain(
      "freshness.expiresAt",
    );
  });

  it("shows start-window countdown", () => {
    expect(panel).toContain(
      "Start Window Guidance",
    );

    expect(panel).toContain(
      'padStart(',
    );
  });

  it("warns when expiration is approaching", () => {
    expect(panel).toContain(
      "close to expiration",
    );

    expect(panel).toContain(
      "start window is getting short",
    );
  });

  it("requires rerun after expiration", () => {
    expect(panel).toContain(
      "Rerun it before game start.",
    );
  });
});
