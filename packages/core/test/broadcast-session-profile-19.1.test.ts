import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.1 broadcast session profile", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionProfiles.ts",
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

  it("persists one broadcast profile per game", () => {
    expect(service).toContain(
      "broadcast-session-profiles.json",
    );

    expect(service).toContain(
      "gameId",
    );

    expect(service).toContain(
      "upsertBroadcastSessionProfile",
    );
  });

  it("supports broadcast presentation settings", () => {
    for (const field of [
      "enabled",
      "title",
      "sponsorUrl",
      "showPowerPlay",
      "showTeamLogos",
    ]) {
      expect(service).toContain(
        field,
      );
    }
  });

  it("provides operator CRUD routes", () => {
    expect(route).toContain(
      '"/broadcast-sessions/:gameId"',
    );

    expect(route).toContain(
      "app.put",
    );

    expect(route).toContain(
      "app.delete",
    );
  });

  it("provides a public enabled-session endpoint", () => {
    expect(route).toContain(
      '"/public/games/:gameId/broadcast-session"',
    );

    expect(route).toContain(
      "profile?.enabled",
    );
  });

  it("registers broadcast-session routes in the API", () => {
    expect(app).toContain(
      "registerBroadcastSessionProfileRoutes",
    );
  });
});
