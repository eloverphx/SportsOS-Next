import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.12.1 Unraid schedule verifier repair", () => {
  const script = fs.readFileSync(
    "scripts/verify-scheduled-production-operations.sh",
    "utf8",
  );

  it("verifies SportsOS ownership through executable wrappers", () => {
    expect(script).toContain('grep -Fq "SportsOS-Next"');
    expect(script).toContain('grep -Fq "run-production-operations.sh"');
  });

  it("supports cron metadata stored anywhere in a User Scripts entry", () => {
    expect(script).toContain("grep -R -F -q");
    expect(script).toContain("--exclude=script");
  });

  it("does not falsely require a specific schedule filename", () => {
    expect(script).not.toContain('[[ -f "$dir/schedule" ]] || return 1');
  });

  it("still executes production verification checks", () => {
    expect(script).toContain("observability-refresh");
    expect(script).toContain("Recovery execution");
    expect(script).toContain("Alert execution");
    expect(script).toContain("data/operations-status/latest.json");
  });
});
