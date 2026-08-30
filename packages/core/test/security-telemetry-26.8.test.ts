import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.8 security telemetry / operator visibility", () => {
  it("provides security telemetry API and dashboard",()=> {
    const route =
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/security/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/security-telemetry"',
    );

    expect(page).toContain(
      "Security Telemetry",
    );

    expect(page).toContain(
      "Security Gate",
    );

    expect(page).toContain(
      "BLOCKED",
    );
  });

  it("keeps dashboard read-only",()=> {
    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/security/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(page).not.toContain(
      'method: "POST"',
    );

    expect(page).not.toContain(
      'method: "DELETE"',
    );
  });
});
