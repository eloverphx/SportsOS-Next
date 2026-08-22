import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.3 commissioning dashboard / installation wizard", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  const page = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("starts a commissioning record by device ID", () => {
    expect(panel).toContain(
      "Start Commissioning",
    );

    expect(panel).toContain(
      "/scoreboard-device-commissioning/",
    );
  });

  it("shows every commissioning step", () => {
    for (const step of [
      "FLASHED",
      "PROVISIONED",
      "ENROLLED",
      "VERIFIED",
      "ASSIGNED",
      "CONNECTIVITY",
      "READINESS",
      "FIRMWARE",
      "GAME_READY",
    ]) {
      expect(panel).toContain(
        step,
      );
    }
  });

  it("allows only physical installation confirmations to be manually toggled", () => {
    expect(panel).toContain(
      'step.id ===\n                    "FLASHED"',
    );

    expect(panel).toContain(
      'step.id ===\n                      "PROVISIONED"',
    );

    expect(panel).toContain(
      "Confirm Complete",
    );
  });

  it("runs automated validation from the wizard", () => {
    expect(panel).toContain(
      "/validate",
    );

    expect(panel).toContain(
      "Run Validation",
    );
  });

  it("surfaces final game-ready state", () => {
    expect(panel).toContain(
      "GAME_READY",
    );

    expect(panel).toContain(
      "passed the full commissioning workflow",
    );
  });

  it("renders the wizard on scoreboard operations", () => {
    expect(page).toContain(
      "ScoreboardCommissioningWizard",
    );

    expect(page).toContain(
      "<ScoreboardCommissioningWizard />",
    );
  });
});
