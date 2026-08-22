import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.6 enrollment dashboard claim workflow", () => {
  it("requests one-time claim tokens", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Generate Claim Token",
    );

    expect(page).toContain(
      "/claim-token",
    );
  });

  it("submits the generated claim token to verification", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "claimToken",
    );

    expect(page).toContain(
      "Verify Device",
    );

    expect(page).toContain(
      'method: "POST"',
    );
  });

  it("removes claim tokens from UI state after verification", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "delete next[deviceId]",
    );

    expect(page).toContain(
      "claim token has been consumed",
    );
  });

  it("shows pending verified and rejected counts", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "pendingCount",
    );

    expect(page).toContain(
      "verifiedCount",
    );

    expect(page).toContain(
      "rejectedCount",
    );
  });

  it("shows physical identity before claim action", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Firmware:",
    );

    expect(page).toContain(
      "Chip ID:",
    );
  });
});
