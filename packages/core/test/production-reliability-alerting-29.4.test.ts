import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.4 production reliability alerting",
  () => {
    const alertScript =
      fs.readFileSync(
        new URL(
          "../../../scripts/production-reliability-alert-check.sh",
          import.meta.url,
        ),
        "utf8",
      );

    const runner =
      fs.readFileSync(
        new URL(
          "../../../scripts/run-production-operations.sh",
          import.meta.url,
        ),
        "utf8",
      );

    it("runs the reliability scorecard", () => {
      expect(alertScript).toContain(
        "scripts/operations-reliability-scorecard.sh",
      );
    });

    it("fingerprints issue sets for deduplication", () => {
      expect(alertScript).toContain("createHash");
      expect(alertScript).toContain("lastFingerprint");
    });

    it("supports a cooldown window", () => {
      expect(alertScript).toContain(
        "SPORTSOS_RELIABILITY_ALERT_COOLDOWN_MINUTES",
      );
      expect(alertScript).toContain("insideCooldown");
    });

    it("supports local-only operation and optional webhook delivery", () => {
      expect(alertScript).toContain(
        "SPORTSOS_RELIABILITY_ALERT_WEBHOOK_URL",
      );
      expect(alertScript).toContain(
        "local alert recorded",
      );
    });

    it("is available through the scheduled operations runner", () => {
      expect(runner).toContain("reliability-alert");
      expect(runner).toContain(
        "scripts/production-reliability-alert-check.sh",
      );
    });

    it("does not perform destructive recovery", () => {
      expect(alertScript).not.toContain("docker restart");
      expect(alertScript).not.toContain("docker compose down");
      expect(alertScript).not.toContain("SPORTSOS_APPLY_ROLLBACK=1");
    });
  },
);
