import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.3 stream destination readiness / connection probe", () => {
  const probe =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationProbe.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const profile =
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

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("uses a TCP reachability probe", () => {
    expect(probe).toContain(
      "net.createConnection",
    );
  });

  it("uses protocol default ports", () => {
    expect(probe).toContain("1935");
    expect(probe).toContain("9000");
  });

  it("persists probe readiness", () => {
    expect(profile).toContain(
      "lastProbeAt",
    );

    expect(profile).toContain(
      "lastProbeLatencyMs",
    );
  });

  it("provides an operator probe route", () => {
    expect(route).toContain(
      '"/stream-destinations/:gameId/probe"',
    );
  });

  it("provides dashboard probe controls", () => {
    expect(panel).toContain(
      "Probe Destination",
    );

    expect(panel).toContain(
      "Last probe",
    );
  });

  it("does not transmit credentials from the probe service", () => {
    expect(probe).not.toContain(
      "credentialRef",
    );
  });
});
