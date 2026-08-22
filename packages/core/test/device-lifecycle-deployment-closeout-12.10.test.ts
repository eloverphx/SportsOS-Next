import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.10 device lifecycle / deployment closeout", () => {
  it("adds retired enrollment state", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      '"RETIRED"',
    );

    expect(service).toContain(
      "retiredAt",
    );
  });

  it("supports retirement and reactivation", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "retireEnrollment",
    );

    expect(service).toContain(
      "reactivateEnrollment",
    );

    expect(service).toContain(
      '"PENDING" as const',
    );
  });

  it("exposes retire and reactivate API routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/retire",
    );

    expect(routes).toContain(
      "/reactivate",
    );
  });

  it("adds lifecycle controls to enrollment dashboard", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Retire Device",
    );

    expect(page).toContain(
      "Reactivate",
    );

    expect(page).toContain(
      "retiredCount",
    );
  });

  it("documents the deployment lifecycle and release gate", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/DEPLOYMENT-READINESS-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "FLASHED",
    );

    expect(checklist).toContain(
      "VERIFIED",
    );

    expect(checklist).toContain(
      "ACTIVE",
    );

    expect(checklist).toContain(
      "RETIRED",
    );

    expect(checklist).toContain(
      "Milestone 12 release gate",
    );
  });
});
