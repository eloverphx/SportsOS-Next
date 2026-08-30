import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.4 backup restore rehearsal", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/backup-restore-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("uses an isolated temporary MySQL database",()=> {
    expect(script).toContain(
      "sportsos_restore_rehearsal_",
    );

    expect(script).toContain(
      "CREATE DATABASE",
    );

    expect(script).toContain(
      "DROP DATABASE IF EXISTS",
    );
  });

  it("does not restore over the production database",()=> {
    expect(script).not.toContain(
      'mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"',
    );
  });

  it("extracts MinIO and data backups into rehearsal workspace",()=> {
    expect(script).toContain(
      '$RUN_DIR/minio',
    );

    expect(script).toContain(
      '$RUN_DIR/data',
    );
  });

  it("validates archive integrity first",()=> {
    expect(script).toContain(
      "gzip -t",
    );

    expect(script).toContain(
      "tar -tzf",
    );
  });

  it("validates restored table count",()=> {
    expect(script).toContain(
      "information_schema.tables",
    );

    expect(script).toContain(
      "TABLE_COUNT",
    );
  });
});
