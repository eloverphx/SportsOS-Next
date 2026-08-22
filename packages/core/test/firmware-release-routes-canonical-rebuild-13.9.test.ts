import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.9 canonical firmware release routes", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("contains exactly one device-offer route", () => {
    const matches =
      source.match(
        /"\/scoreboard-firmware\/device-offer"/g,
      ) ?? [];

    expect(matches).toHaveLength(1);
  });

  it("keeps /latest independent from rollout state", () => {
    const latestStart =
      source.indexOf(
        '"/scoreboard-firmware/latest"',
      );

    const deviceOfferStart =
      source.indexOf(
        '"/scoreboard-firmware/device-offer"',
      );

    expect(latestStart).toBeGreaterThan(
      -1,
    );

    expect(deviceOfferStart).toBeGreaterThan(
      latestStart,
    );

    const latestBlock =
      source.slice(
        latestStart,
        deviceOfferStart,
      );

    expect(latestBlock).toContain(
      "getLatestCompatibleFirmwareRelease",
    );

    expect(latestBlock).not.toContain(
      "rollout.",
    );

    expect(latestBlock).not.toContain(
      "findActiveRolloutForDevice",
    );
  });

  it("declares rollout before all rollout uses in device-offer", () => {
    const start =
      source.indexOf(
        '"/scoreboard-firmware/device-offer"',
      );

    const route =
      source.slice(start);

    const declaration =
      route.indexOf(
        "const rollout =",
      );

    expect(declaration).toBeGreaterThan(
      -1,
    );

    for (const token of [
      "rollout.releaseId",
      "rollout.rolloutId",
      "rollout.state",
    ]) {
      const use =
        route.indexOf(token);

      expect(use).toBeGreaterThan(
        declaration,
      );
    }
  });

  it("preserves verified-device rollout gating", () => {
    expect(source).toContain(
      "isVerifiedDevice",
    );

    expect(source).toContain(
      "findActiveRolloutForDevice",
    );

    expect(source).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("preserves the five intended release routes", () => {
    for (const route of [
      "/scoreboard-firmware/releases",
      "/scoreboard-firmware/releases/:releaseId",
      "/scoreboard-firmware/latest",
      "/scoreboard-firmware/device-offer",
    ]) {
      expect(source).toContain(route);
    }

    expect(source).toContain(
      "app.post(",
    );
  });
});
