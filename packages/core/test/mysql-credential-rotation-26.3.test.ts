import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.3 MySQL credential rotation workflow", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-mysql-password.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("defaults to preflight only",()=> {
    expect(script).toContain(
      'APPLY="${SPORTSOS_APPLY_ROTATION:-0}"',
    );
    expect(script).toContain(
      "No credential was changed.",
    );
  });

  it("validates current application credential before changing anything",()=> {
    expect(script).toContain(
      "current MYSQL_PASSWORD in .env does not authenticate successfully",
    );
    expect(script).toContain(
      'mysql "-u${MYSQL_USER}"',
    );
  });

  it("validates administrative credential",()=> {
    expect(script).toContain(
      "MYSQL_ROOT_PASSWORD in .env does not authenticate as MySQL root",
    );
  });

  it("updates database account before environment file",()=> {
    const alterIndex =
      script.indexOf(
        "ALTER USER",
      );
    const envIndex =
      script.indexOf(
        "MYSQL_PASSWORD updated in .env",
      );

    expect(alterIndex).toBeGreaterThan(-1);
    expect(envIndex).toBeGreaterThan(alterIndex);
  });

  it("verifies new database credential before API restart",()=> {
    const verifyIndex =
      script.indexOf(
        "Verifying new MySQL application credential",
      );
    const apiIndex =
      script.indexOf(
        "docker compose up -d --force-recreate api",
      );

    expect(verifyIndex).toBeGreaterThan(-1);
    expect(apiIndex).toBeGreaterThan(verifyIndex);
  });

  it("contains automatic rollback for failed immediate credential verification",()=> {
    expect(script).toContain(
      "Restoring old MySQL account password and .env",
    );
  });

  it("does not print the new password",()=> {
    expect(script).not.toContain(
      'echo "$NEW_PASSWORD"',
    );
  });
});
