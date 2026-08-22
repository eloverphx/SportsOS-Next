import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.9 enrollment / hardware operations integration", () => {
  it("keeps enrollment client logic in a dedicated client component", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      '"use client"',
    );

    expect(component).toContain(
      "/scoreboard-devices/enrollment",
    );
  });

  it("shows verified pending rejected and untrusted metrics", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    for (const label of [
      "Verified",
      "Pending",
      "Rejected",
      "Untrusted",
    ]) {
      expect(component).toContain(label);
    }
  });

  it("links hardware operations to enrollment management", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "/scoreboards/enrollment",
    );

    expect(component).toContain(
      "Manage Enrollment",
    );
  });

  it("renders a device enrollment trust badge", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "EnrollmentTrustBadge",
    );

    expect(component).toContain(
      "record.status",
    );
  });

  it("integrates trust panel into the existing operations page without forcing it client-side", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      'import { EnrollmentTrustPanel } from "./EnrollmentTrustPanel";',
    );

    expect(page).toContain(
      "<EnrollmentTrustPanel />",
    );
  });

  it("documents verified-only operational eligibility", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "Only VERIFIED devices are eligible",
    );
  });
});
