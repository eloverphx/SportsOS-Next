import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.10 operations closeout", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/operations-closeout-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("includes backup creation and restore rehearsal",()=> {
    expect(script).toContain(
      "scripts/backup-mysql.sh",
    );

    expect(script).toContain(
      "scripts/backup-persistent-data.sh",
    );

    expect(script).toContain(
      "scripts/backup-restore-rehearsal.sh",
    );
  });

  it("includes production operational checks",()=> {
    expect(script).toContain(
      "scripts/production-health-monitor.sh",
    );

    expect(script).toContain(
      "scripts/production-alert-check.sh",
    );

    expect(script).toContain(
      "scripts/container-recovery-check.sh",
    );

    expect(script).toContain(
      "scripts/log-retention-check.sh",
    );
  });

  it("keeps rollback in dry-run mode",()=> {
    expect(script).toContain(
      "scripts/production-rollback.sh",
    );

    expect(script).not.toContain(
      "SPORTSOS_APPLY_ROLLBACK=1",
    );
  });

  it("includes full test coverage",()=> {
    expect(script).toContain(
      "npm run typecheck && npm test",
    );

    expect(script).toContain(
      "npm run test:e2e:docker",
    );
  });

  it("writes protected closeout report",()=> {
    expect(script).toContain(
      "data/operations-closeout",
    );

    expect(script).toContain(
      "chmod 600",
    );
  });
});
