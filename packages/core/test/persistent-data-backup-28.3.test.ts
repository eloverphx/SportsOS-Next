import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.3 persistent data backups", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/backup-persistent-data.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("backs up MinIO host data mount",()=> {
    expect(script).toContain(
      'eq .Destination "/data"',
    );

    expect(script).toContain(
      "sportsos-minio-",
    );
  });

  it("backs up SportsOS persistent data",()=> {
    expect(script).toContain(
      "sportsos-data-",
    );

    expect(script).toContain(
      "--exclude='data/backups'",
    );
  });

  it("verifies tar integrity",()=> {
    expect(script).toContain(
      "tar -tzf",
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
      "SPORTSOS_DATA_BACKUP_RETENTION_DAYS",
    );

    expect(script).toContain(
      "-mtime",
    );

    expect(script).toContain(
      "-delete",
    );
  });

  it("does not print MinIO password",()=> {
    expect(script).not.toContain(
      'echo "$MINIO_PASSWORD"',
    );
  });
});
