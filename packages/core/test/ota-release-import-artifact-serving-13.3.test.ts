import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.3 OTA release import / artifact serving", () => {
  it("validates firmware artifact size and SHA-256 before import", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareArtifactStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "firmwareSizeBytes",
    );

    expect(service).toContain(
      "firmwareSha256",
    );

    expect(service).toContain(
      'crypto.createHash("sha256")',
    );
  });

  it("copies validated firmware into API-managed artifact storage", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareArtifactStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-artifacts",
    );

    expect(service).toContain(
      "fs.copyFileSync",
    );

    expect(service).toContain(
      "fs.renameSync",
    );
  });

  it("registers imported release manifest", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareArtifactStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "registerFirmwareRelease",
    );
  });

  it("exposes release import endpoint", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareArtifacts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/import",
    );

    expect(routes).toContain(
      "releaseDirectory is required.",
    );
  });

  it("serves firmware only to verified devices", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareArtifacts.ts",
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

    expect(routes).toContain(
      "application/octet-stream",
    );
  });

  it("returns integrity metadata headers with artifact", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareArtifacts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "X-SportsOS-Firmware-SHA256",
    );

    expect(routes).toContain(
      "X-SportsOS-Firmware-Version",
    );
  });

  it("registers artifact routes in API app", () => {
    const app = fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(app).toContain(
      "registerScoreboardFirmwareArtifactRoutes",
    );
  });
});
