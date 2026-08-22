import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.9 device-offer handler replacement repair", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const routeStart =
    source.indexOf(
      '"/scoreboard-firmware/device-offer"',
    );

  const route =
    source.slice(
      routeStart,
    );

  it("declares rollout before rollout.releaseId", () => {
    expect(routeStart).toBeGreaterThan(
      -1,
    );

    const declaration =
      route.indexOf(
        "const rollout =",
      );

    const firstUse =
      route.indexOf(
        "rollout.releaseId",
      );

    expect(declaration).toBeGreaterThan(
      -1,
    );

    expect(firstUse).toBeGreaterThan(
      declaration,
    );
  });

  it("requires verified devices", () => {
    expect(route).toContain(
      "isVerifiedDevice",
    );

    expect(route).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("returns no offer without an active rollout", () => {
    expect(route).toContain(
      "findActiveRolloutForDevice",
    );

    expect(route).toContain(
      "rollout: null",
    );

    expect(route).toContain(
      "updateAvailable: false",
    );
  });

  it("selects the rollout release directly", () => {
    expect(route).toContain(
      "getFirmwareRelease",
    );

    expect(route).toContain(
      "rollout.releaseId",
    );
  });

  it("returns device-bound artifact URL when update is available", () => {
    expect(route).toContain(
      "artifactUrl",
    );

    expect(route).toContain(
      "deviceId=",
    );

    expect(route).toContain(
      "updateAvailable: true",
    );
  });
});
