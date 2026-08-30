import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.5 operations status snapshot",
  () => {
    const script =
      fs.readFileSync(
        new URL(
          "../../../scripts/operations-status-snapshot.sh",
          import.meta.url,
        ),
        "utf8",
      );

    it("refreshes reliability before generating the snapshot", () => {
      expect(script).toContain(
        "scripts/operations-reliability-scorecard.sh",
      );
    });

    it("creates a stable latest snapshot", () => {
      expect(script).toContain(
        'LATEST_FILE="${SNAPSHOT_DIR}/latest.json"',
      );
      expect(script).toContain("copyFileSync");
    });

    it("includes current operational categories", () => {
      expect(script).toContain("health:");
      expect(script).toContain("backup:");
      expect(script).toContain("recovery:");
      expect(script).toContain("restoreRehearsal:");
      expect(script).toContain("reliabilityAlert:");
    });

    it("includes recent run and failure totals", () => {
      expect(script).toContain("totalRuns");
      expect(script).toContain("failedRuns");
      expect(script).toContain("passedRuns");
    });

    it("does not emit raw logs or webhook configuration", () => {
      expect(script).not.toContain("runLog:");
      expect(script).not.toContain("WEBHOOK_URL");
    });

    it("keeps generated snapshots protected", () => {
      expect(script).toContain("chmod 600");
    });
  },
);
