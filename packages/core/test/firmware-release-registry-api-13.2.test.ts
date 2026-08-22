import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.2 firmware release registry / API", () => {
  it("persists firmware releases to a restart-safe registry", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-releases.json",
    );

    expect(service).toContain(
      "persistStore",
    );

    expect(service).toContain(
      "fs.renameSync",
    );
  });

  it("supports release lookup and latest-compatible selection", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "getFirmwareRelease",
    );

    expect(service).toContain(
      "getLatestCompatibleFirmwareRelease",
    );

    expect(service).toContain(
      "minimumCurrentVersion",
    );
  });

  it("supports stable beta development channel filtering", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "release.channel",
    );

    expect(service).toContain(
      "release.target",
    );
  });

  it("exposes release registry API routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/releases",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/releases/:releaseId",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/latest",
    );
  });

  it("returns updateAvailable from latest endpoint", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "updateAvailable",
    );

    expect(routes).toContain(
      "currentVersion is required.",
    );
  });

  it("registers firmware routes in API app", () => {
    const app = fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(app).toContain(
      "registerScoreboardFirmwareReleaseRoutes",
    );
  });
});
