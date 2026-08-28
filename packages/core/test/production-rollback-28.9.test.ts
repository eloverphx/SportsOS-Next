import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.9 production rollback", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/production-rollback.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("defaults to a known-good release tag",()=> {
    expect(script).toContain(
      'SPORTSOS_ROLLBACK_TARGET:-sportsos-m27-complete',
    );
  });

  it("requires a clean working tree",()=> {
    expect(script).toContain(
      "git status --porcelain",
    );

    expect(script).toContain(
      "working tree is not clean",
    );
  });

  it("creates backups before rollback",()=> {
    expect(script).toContain(
      "scripts/capture-production-baseline.sh",
    );

    expect(script).toContain(
      "scripts/backup-mysql.sh",
    );

    expect(script).toContain(
      "scripts/backup-persistent-data.sh",
    );
  });

  it("is dry-run by default",()=> {
    expect(script).toContain(
      'APPLY="${SPORTSOS_APPLY_ROLLBACK:-0}"',
    );

    expect(script).toContain(
      "DRY RUN COMPLETE",
    );
  });

  it("only checks out target when explicitly enabled",()=> {
    expect(script).toContain(
      'if [[ "$APPLY" != "1" ]]',
    );

    expect(script).toContain(
      'git checkout --detach "$TARGET_COMMIT"',
    );
  });

  it("validates health after rollback",()=> {
    expect(script).toContain(
      "scripts/production-health-monitor.sh",
    );
  });
});
