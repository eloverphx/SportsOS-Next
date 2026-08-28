import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.7.2 dashboard relative import repair",
  () => {
    const page =
      fs.readFileSync(
        "apps/dashboard/app/dashboard/operations/page.tsx",
        "utf8",
      );

    const helper =
      fs.readFileSync(
        "apps/dashboard/app/dashboard/operations/operationsStatus.ts",
        "utf8",
      );

    it("uses a colocated relative server helper", () => {
      expect(page).toContain(
        'from "./operationsStatus"',
      );
      expect(page).not.toContain(
        'from "@/lib/operationsStatus"',
      );
      expect(helper).toContain(
        'import "server-only"',
      );
    });

    it("explicitly types issue rendering", () => {
      expect(page).toContain(
        "issue: ReliabilityIssue",
      );
      expect(page).toContain(
        "index: number",
      );
    });

    it("keeps the operations token out of page code", () => {
      expect(page).not.toContain(
        "SPORTSOS_OPERATIONS_STATUS_TOKEN",
      );
      expect(page).not.toContain("Authorization:");
    });

    it("keeps protected API access server-side", () => {
      expect(helper).toContain(
        "SPORTSOS_OPERATIONS_STATUS_TOKEN",
      );
      expect(helper).toContain(
        "/deployment/operations/status",
      );
      expect(helper).toContain(
        'cache: "no-store"',
      );
    });
  },
);
