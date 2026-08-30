import fs from "node:fs";
import {
  describe,
  expect,
  it,
} from "vitest";

describe(
  "Milestone 29.1 scheduled production operations",
  () => {
    const script =
      fs.readFileSync(
        new URL(
          "../../../scripts/run-production-operations.sh",
          import.meta.url,
        ),
        "utf8",
      );

    it(
      "uses flock to prevent overlapping runs",
      () => {
        expect(script).toContain(
          "flock",
        );

        expect(script).toContain(
          "operations-locks",
        );
      },
    );

    it(
      "supports production maintenance modes",
      () => {
        expect(script).toContain(
          "mysql-backup",
        );

        expect(script).toContain(
          "persistent-backup",
        );

        expect(script).toContain(
          "restore-rehearsal",
        );

        expect(script).toContain(
          "daily",
        );

        expect(script).toContain(
          "weekly",
        );
      },
    );

    it(
      "reuses existing operational scripts",
      () => {
        expect(script).toContain(
          "scripts/production-alert-check.sh",
        );

        expect(script).toContain(
          "scripts/container-recovery-check.sh",
        );

        expect(script).toContain(
          "scripts/backup-mysql.sh",
        );

        expect(script).toContain(
          "scripts/backup-persistent-data.sh",
        );

        expect(script).toContain(
          "scripts/backup-restore-rehearsal.sh",
        );

        expect(script).toContain(
          "scripts/log-retention-check.sh",
        );
      },
    );

    it(
      "does not add destructive recovery behavior",
      () => {
        expect(script).not.toContain(
          "docker compose down",
        );

        expect(script).not.toContain(
          "SPORTSOS_APPLY_ROLLBACK=1",
        );
      },
    );

    it(
      "writes protected run logs",
      () => {
        expect(script).toContain(
          "operations-runs",
        );

        expect(script).toContain(
          "chmod 600",
        );
      },
    );
  },
);
