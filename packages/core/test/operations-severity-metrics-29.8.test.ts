import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.8 reliability severity metrics",
  () => {
    const script = fs.readFileSync(
      "scripts/operations-severity-metrics.sh",
      "utf8",
    );

    it("reads operations history and reliability data", () => {
      expect(script).toContain("data/operations-history");
      expect(script).toContain("data/operations-reliability");
    });

    it("writes protected metrics snapshots", () => {
      expect(script).toContain("data/operations-metrics");
      expect(script).toContain('path.join(outputDir, "latest.json")');
      expect(script).toContain("mode: 0o600");
    });

    it("defines normalized severity", () => {
      expect(script).toContain('let severity = "healthy"');
      expect(script).toContain('"warning"');
      expect(script).toContain('"critical"');
    });

    it("uses failure rate and streak thresholds", () => {
      expect(script).toContain("warningFailureRate");
      expect(script).toContain("criticalFailureRate");
      expect(script).toContain("warningStreak");
      expect(script).toContain("criticalStreak");
    });

    it("does not include operational secrets", () => {
      expect(script).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
      expect(script).not.toContain("WEBHOOK_URL");
      expect(script).not.toContain("backups/mysql/");
    });

    it("uses distinct severity exit codes", () => {
      expect(script).toContain('severity === "critical"');
      expect(script).toContain("? 3");
      expect(script).toContain('severity === "warning"');
      expect(script).toContain("? 2");
    });
  },
);
