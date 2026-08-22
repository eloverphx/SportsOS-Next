import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.8 firmware fleet operations dashboard", () => {
  const page = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/firmware/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("loads firmware releases and deployment reports", () => {
    expect(page).toContain(
      "/scoreboard-firmware/releases",
    );

    expect(page).toContain(
      "/scoreboard-firmware/deployments",
    );
  });

  it("shows release updating succeeded and failed metrics", () => {
    for (const label of [
      "Releases",
      "Updating",
      "Succeeded",
      "Failed",
    ]) {
      expect(page).toContain(label);
    }
  });

  it("shows current and target versions per device", () => {
    expect(page).toContain(
      "previousVersion",
    );

    expect(page).toContain(
      "targetVersion",
    );
  });

  it("shows progress and deployment errors", () => {
    expect(page).toContain(
      "progressPercent",
    );

    expect(page).toContain(
      "report.error",
    );
  });

  it("links back to hardware operations", () => {
    expect(page).toContain(
      "/scoreboards/operations",
    );
  });

  it("links hardware operations to firmware fleet", () => {
    const operations = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(operations).toContain(
      "/scoreboards/firmware",
    );

    expect(operations).toContain(
      "Firmware Fleet",
    );
  });
});
