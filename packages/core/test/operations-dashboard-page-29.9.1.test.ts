import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.9.1 operations dashboard page repair", () => {
  const page = fs.readFileSync(
    "apps/dashboard/app/dashboard/operations/page.tsx",
    "utf8",
  );

  it("uses the colocated server helper", () => {
    expect(page).toContain('from "./operationsStatus"');
  });

  it("renders the severity summary", () => {
    expect(page).toContain("Operations severity");
    expect(page).toContain("data.severity.status");
    expect(page).toContain("data.severity.summary.failureRatePercent");
    expect(page).toContain("data.severity.summary.maxFailureStreak");
  });

  it("renders the six production operation cards", () => {
    expect(page).toContain('title="Health"');
    expect(page).toContain('title="MySQL backup"');
    expect(page).toContain('title="Persistent backup"');
    expect(page).toContain('title="Recovery"');
    expect(page).toContain('title="Restore rehearsal"');
    expect(page).toContain('title="Reliability alert"');
  });

  it("renders reliability issues without implicit any callbacks", () => {
    expect(page).toContain("data.reliability.issues.map");
    expect(page).toContain("SeverityReason");
  });

  it("does not expose operations credentials", () => {
    expect(page).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(page).not.toContain("Authorization:");
  });
});
