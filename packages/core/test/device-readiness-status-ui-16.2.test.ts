import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.2 device readiness status UI", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("loads scoreboard assignments", () => {
    expect(panel).toContain(
      "/scoreboard-devices/assignments",
    );
  });

  it("queries server readiness for assigned devices", () => {
    expect(panel).toContain(
      "/scoreboard-control-readiness/",
    );

    expect(panel).toContain(
      "DeviceReadiness",
    );
  });

  it("renders device readiness status", () => {
    expect(panel).toContain(
      "Device Readiness Status",
    );

    expect(panel).toContain(
      "READY",
    );

    expect(panel).toContain(
      "NOT READY",
    );
  });

  it("shows game, device, heartbeat age, and detail", () => {
    for (const value of [
      "Device",
      "Game",
      "Heartbeat Age",
      "Detail",
    ]) {
      expect(panel).toContain(
        value,
      );
    }
  });

  it("does not make readiness authoritative in the browser", () => {
    expect(panel).toContain(
      "/scoreboard-control-readiness/",
    );

    expect(panel).not.toContain(
      "localStorage.setItem(\"deviceReadiness",
    );
  });
});
