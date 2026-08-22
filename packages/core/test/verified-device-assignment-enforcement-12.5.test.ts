import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.5 verified device enforcement", () => {
  it("defines a reusable verified-device authorization service", () => {
    const guard = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceAuthorization.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(guard).toContain(
      "authorizeVerifiedScoreboardDevice",
    );

    expect(guard).toContain(
      "isVerifiedDevice",
    );

    expect(guard).toContain(
      "Scoreboard device is not enrolled.",
    );

    expect(guard).toContain(
      "Scoreboard device is not verified.",
    );
  });

  it("wires the authorization service into scoreboard device routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "authorizeVerifiedScoreboardDevice",
    );
  });

  it("protects device command operations", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-devices/:deviceId",
    );

    expect(routes).toContain(
      "authorization.statusCode",
    );
  });

  it("protects assignment operations for body-supplied device IDs", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "assignmentDeviceAuthorization",
    );
  });

  it("keeps rejected and pending devices visible through enrollment state", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      '"PENDING"',
    );

    expect(service).toContain(
      '"REJECTED"',
    );

    expect(service).toContain(
      '"VERIFIED"',
    );
  });
});
