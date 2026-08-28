import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.12.2 exact Unraid User Scripts verifier", () => {
  const script = fs.readFileSync(
    "scripts/verify-scheduled-production-operations.sh",
    "utf8",
  );

  it("verifies the discovered two-line custom schedule format", () => {
    expect(script).toContain(
      '[[ "$schedule_line1" == "custom" ]]',
    );
    expect(script).toContain(
      '[[ "$schedule_line2" == "$expected_schedule" ]]',
    );
  });

  it("does not require an executable bit on the flash-backed outer script", () => {
    expect(script).not.toContain('[[ -x "$outer" ]]');
    expect(script).toContain(
      "discovered flash metadata reports mode 0600",
    );
  });

  it("verifies the outer script delegates to the repository wrapper", () => {
    expect(script).toContain(
      'grep -Fq "exec bash \\"$delegated\\"" "$outer"',
    );
  });

  it("verifies the operation mode in the delegated wrapper", () => {
    expect(script).toContain(
      'run-production-operations.sh $expected_mode',
    );
  });

  it("retains all runtime closeout checks", () => {
    expect(script).toContain("Observability refresh execution");
    expect(script).toContain("Recovery execution");
    expect(script).toContain("Alert execution");
    expect(script).toContain(
      "data/operations-status/latest.json",
    );
    expect(script).toContain(
      "data/operations-metrics/latest.json",
    );
  });
});
