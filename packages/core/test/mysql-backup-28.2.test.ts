import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.2 automated MySQL backups", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/backup-mysql.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("uses transactional mysqldump",()=> {
    expect(script).toContain(
      "--single-transaction",
    );

    expect(script).toContain(
      "--quick",
    );
  });

  it("compresses and verifies backups",()=> {
    expect(script).toContain(
      "gzip -9",
    );

    expect(script).toContain(
      "gzip -t",
    );
  });

  it("uses restrictive permissions",()=> {
    expect(script).toContain(
      "umask 077",
    );

    expect(script).toContain(
      "chmod 600",
    );

    expect(script).toContain(
      "chmod 700",
    );
  });

  it("implements retention",()=> {
    expect(script).toContain(
      "SPORTSOS_MYSQL_BACKUP_RETENTION_DAYS",
    );

    expect(script).toContain(
      "-mtime",
    );

    expect(script).toContain(
      "-delete",
    );
  });

  it("does not print database password",()=> {
    expect(script).not.toContain(
      'echo "$MYSQL_PASSWORD"',
    );
  });
});
