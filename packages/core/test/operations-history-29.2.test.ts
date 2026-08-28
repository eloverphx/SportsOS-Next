import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.2 operations history",
  () => {
    const runner =
      fs.readFileSync(
        new URL(
          "../../../scripts/run-production-operations.sh",
          import.meta.url,
        ),
        "utf8",
      );

    const report =
      fs.readFileSync(
        new URL(
          "../../../scripts/operations-history-report.sh",
          import.meta.url,
        ),
        "utf8",
      );

    it("writes protected JSON history records", () => {
      expect(runner).toContain("operations-history");
      expect(runner).toContain("JSON.stringify");
      expect(runner).toContain("chmod 600");
    });

    it("records operation status and exit code", () => {
      expect(runner).toContain('status="failed"');
      expect(runner).toContain("exitCode");
    });

    it("links history back to raw run logs", () => {
      expect(runner).toContain("runLog");
    });

    it("supports rolling trend windows", () => {
      expect(report).toContain("SPORTSOS_OPERATIONS_HISTORY_DAYS");
      expect(report).toContain("Failures in window");
    });

    it("does not expose history as a public route", () => {
      expect(runner).not.toContain("fastify.get");
      expect(report).not.toContain("fastify.get");
    });
  },
);
