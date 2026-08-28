import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.3 production reliability scorecard",
  () => {
    const script =
      fs.readFileSync(
        new URL(
          "../../../scripts/operations-reliability-scorecard.sh",
          import.meta.url,
        ),
        "utf8",
      );

    it("calculates rolling success percentages", () => {
      expect(script).toContain("successPercent");
      expect(script).toContain("minSuccessPercent");
    });

    it("detects consecutive failure streaks", () => {
      expect(script).toContain("currentFailureStreak");
      expect(script).toContain("maxFailureStreak");
    });

    it("detects stale health activity", () => {
      expect(script).toContain("staleHealthMinutes");
      expect(script).toContain("stale-health");
    });

    it("detects stale backup activity", () => {
      expect(script).toContain("staleBackupHours");
      expect(script).toContain("stale-backup");
    });

    it("writes protected machine-readable output", () => {
      expect(script).toContain("operations-reliability");
      expect(script).toContain("JSON.stringify");
      expect(script).toContain("chmod 600");
    });

    it("remains diagnostic and non-destructive", () => {
      expect(script).not.toContain("docker restart");
      expect(script).not.toContain("docker compose down");
      expect(script).not.toContain("SPORTSOS_APPLY_ROLLBACK=1");
    });
  },
);
