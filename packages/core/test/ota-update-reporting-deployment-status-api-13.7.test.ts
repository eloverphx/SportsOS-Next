import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.7 OTA update reporting / deployment status API", () => {
  it("persists deployment reports", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareDeploymentStatus.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-deployments.json",
    );

    expect(service).toContain(
      "recordFirmwareDeploymentStatus",
    );
  });

  it("exposes report, history, and latest endpoints", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/deployments/report",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/deployments",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/deployments/:deviceId/latest",
    );
  });

  it("requires verified device identity for update reports", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "isVerifiedDevice",
    );

    expect(routes).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("defines ESP32 firmware update reporter", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareUpdateReporter.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareUpdateReporter",
    );

    expect(header).toContain(
      "FirmwareUpdateState",
    );
  });

  it("posts deployment status to SportsOS API", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateReporter.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "/scoreboard-firmware/deployments/report",
    );

    expect(source).toContain(
      "progressPercent",
    );

    expect(source).toContain(
      "targetVersion",
    );
  });

  it("registers deployment status routes in API app", () => {
    const app = fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(app).toContain(
      "registerScoreboardFirmwareDeploymentStatusRoutes",
    );
  });
});
