import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.12 scheduled operations verification", () => {
  const script = fs.readFileSync(
    "scripts/verify-scheduled-production-operations.sh",
    "utf8",
  );

  it("checks all four Unraid schedules", () => {
    expect(script).toContain("SportsOS Observability");
    expect(script).toContain("SportsOS Recovery");
    expect(script).toContain("SportsOS Daily Operations");
    expect(script).toContain("SportsOS Weekly Rehearsal");
  });

  it("checks the intended schedules", () => {
    expect(script).toContain("*/5 * * * *");
    expect(script).toContain("15 3 * * *");
    expect(script).toContain("30 4 * * 0");
  });

  it("executes observability recovery and alert checks", () => {
    expect(script).toContain("observability-refresh");
    expect(script).toContain(" recovery");
    expect(script).toContain(" alert");
  });

  it("verifies generated operations data", () => {
    expect(script).toContain(
      "data/operations-status/latest.json",
    );
    expect(script).toContain(
      "data/operations-metrics/latest.json",
    );
    expect(script).toContain(
      "data/operations-history",
    );
  });

  it("writes a protected closeout report", () => {
    expect(script).toContain(
      "data/operations-scheduled-verification",
    );
    expect(script).toContain("chmod 600");
  });
});
