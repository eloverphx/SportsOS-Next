import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.9 incident-resolution UI recovery", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("restores incident-resolution type and state", () => {
    expect(panel).toContain(
      "type IncidentResolution",
    );

    expect(panel).toContain(
      "incidentResolutions",
    );

    expect(panel).toContain(
      "incidentNotes",
    );
  });

  it("loads incident-resolution inventory", () => {
    expect(panel).toContain(
      "/scoreboard-control-incident-resolutions",
    );
  });

  it("restores acknowledge and resolve actions", () => {
    expect(panel).toContain(
      "updateIncidentResolution",
    );

    expect(panel).toContain(
      "Acknowledge",
    );

    expect(panel).toContain(
      "Resolve",
    );
  });

  it("shows latest incident resolution state", () => {
    expect(panel).toContain(
      "resolutionForIncident",
    );

    expect(panel).toContain(
      "Latest note:",
    );
  });
});
