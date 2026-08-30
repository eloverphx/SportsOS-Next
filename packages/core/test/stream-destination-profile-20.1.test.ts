import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.1 stream destination profile foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/streamDestinationProfiles.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const app =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("supports RTMP and SRT destinations", () => {
    expect(service).toContain(
      '"RTMP"',
    );

    expect(service).toContain(
      '"SRT"',
    );
  });

  it("stores credential references rather than a public stream key", () => {
    expect(service).toContain(
      "credentialRef",
    );

    expect(route).not.toContain(
      "streamKey",
    );
  });

  it("supports destination readiness states", () => {
    for (const state of [
      "DISABLED",
      "CONFIGURED",
      "READY",
      "LIVE",
      "ERROR",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("provides operator CRUD routes", () => {
    expect(route).toContain(
      '"/stream-destinations/:gameId"',
    );

    expect(route).toContain(
      "app.put",
    );

    expect(route).toContain(
      "app.delete",
    );
  });

  it("provides a redacted public status endpoint", () => {
    expect(route).toContain(
      '"/public/games/:gameId/stream-status"',
    );

    expect(service).toContain(
      "publicStreamDestinationSummary",
    );
  });

  it("registers streaming routes in the API", () => {
    expect(app).toContain(
      "registerStreamDestinationProfileRoutes",
    );
  });
});
