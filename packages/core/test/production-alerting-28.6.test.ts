import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.6 production alerting", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/production-alert-check.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("runs the production health monitor",()=> {
    expect(script).toContain(
      "scripts/production-health-monitor.sh",
    );
  });

  it("extracts failures into an incident record",()=> {
    expect(script).toContain(
      "grep '^FAIL  '",
    );

    expect(script).toContain(
      "latest-alert.txt",
    );
  });

  it("deduplicates alerts with cooldown",()=> {
    expect(script).toContain(
      "SPORTSOS_ALERT_COOLDOWN_SECONDS",
    );

    expect(script).toContain(
      "sha256sum",
    );

    expect(script).toContain(
      "SUPPRESSED",
    );
  });

  it("supports optional webhook delivery",()=> {
    expect(script).toContain(
      "SPORTSOS_ALERT_WEBHOOK_URL",
    );

    expect(script).toContain(
      "Content-Type: application/json",
    );
  });

  it("uses restrictive permissions",()=> {
    expect(script).toContain(
      "chmod 700",
    );

    expect(script).toContain(
      "chmod 600",
    );
  });
});
