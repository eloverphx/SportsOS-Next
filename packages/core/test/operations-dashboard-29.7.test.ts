import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.7 authenticated operations dashboard",
  () => {
    const libPath =
      fs.existsSync("apps/dashboard/src/lib/operationsStatus.ts")
        ? "apps/dashboard/src/lib/operationsStatus.ts"
        : "apps/dashboard/lib/operationsStatus.ts";

    const pagePath =
      fs.existsSync("apps/dashboard/src/app/dashboard/operations/page.tsx")
        ? "apps/dashboard/src/app/dashboard/operations/page.tsx"
        : "apps/dashboard/app/dashboard/operations/page.tsx";

    const lib = fs.readFileSync(libPath, "utf8");
    const page = fs.readFileSync(pagePath, "utf8");

    it("keeps operations API access server-only", () => {
      expect(lib).toContain('import "server-only"');
      expect(lib).toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
      expect(lib).toContain("Authorization:");
      expect(page).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
      expect(page).not.toContain("Authorization:");
    });

    it("is disabled separately by default", () => {
      expect(lib).toContain(
        "SPORTSOS_OPERATIONS_DASHBOARD_ENABLED",
      );
      expect(lib).toContain(
        'process.env.SPORTSOS_OPERATIONS_DASHBOARD_ENABLED === "true"',
      );
    });

    it("uses the protected deployment endpoint", () => {
      expect(lib).toContain(
        "/deployment/operations/status",
      );
    });

    it("forces dynamic server rendering and disables fetch caching", () => {
      expect(page).toContain('dynamic = "force-dynamic"');
      expect(lib).toContain('cache: "no-store"');
    });

    it("shows reliability and operational status categories", () => {
      expect(page).toContain("Overall reliability");
      expect(page).toContain("MySQL backup");
      expect(page).toContain("Persistent backup");
      expect(page).toContain("Recovery check");
      expect(page).toContain("Restore rehearsal");
      expect(page).toContain("Reliability issues");
    });

    it("does not expose raw operational storage paths", () => {
      expect(page).not.toContain("operations-runs");
      expect(page).not.toContain("backups/mysql");
      expect(page).not.toContain("/app/data");
    });
  },
);
