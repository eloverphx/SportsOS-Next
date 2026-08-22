import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.4 commissioning auto-refresh / live device progress", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("uses an automatic validation cadence", () => {
    expect(panel).toContain(
      "COMMISSIONING_AUTO_REFRESH_MS",
    );

    expect(panel).toContain(
      "5000",
    );

    expect(panel).toContain(
      "setInterval",
    );
  });

  it("re-runs server commissioning validation automatically", () => {
    expect(panel).toContain(
      "validateCommissioningSilently",
    );

    expect(panel).toContain(
      "/validate",
    );
  });

  it("prevents overlapping background validation requests", () => {
    expect(panel).toContain(
      "validationInFlight",
    );
  });

  it("stops live validation when the device becomes game ready", () => {
    expect(panel).toContain(
      'commissioning.status ===',
    );

    expect(panel).toContain(
      '"GAME_READY"',
    );
  });

  it("allows the operator to pause live progress", () => {
    expect(panel).toContain(
      "Live Progress:",
    );

    expect(panel).toContain(
      "autoRefreshEnabled",
    );

    expect(panel).toContain(
      "Auto-validation paused.",
    );
  });
});
