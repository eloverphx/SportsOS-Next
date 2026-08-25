import fs from "node:fs";
import path from "node:path";

export type DataMigrationReadinessCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type DataMigrationReadinessInput = {
  dataDir:
    string | null;
  files:
    string[];
  mysqlReachable:
    boolean;
};

export type DataMigrationReadinessResult = {
  ready: boolean;
  checks:
    DataMigrationReadinessCheck[];
};

export function evaluateDataMigrationReadiness(
  input: DataMigrationReadinessInput,
): DataMigrationReadinessResult {
  const checks:
    DataMigrationReadinessCheck[] =
    [];

  checks.push({
    id:
      "mysql:reachable",
    ok:
      input.mysqlReachable,
    required:
      true,
    message:
      input.mysqlReachable
        ? "MySQL is reachable."
        : "MySQL is not reachable.",
  });

  const dataDir =
    input.dataDir?.trim() ??
    "";

  checks.push({
    id:
      "data-dir:configured",
    ok:
      Boolean(
        dataDir,
      ),
    required:
      true,
    message:
      dataDir
        ? `Persistent data directory is ${dataDir}.`
        : "Persistent data directory is not configured.",
  });

  if (dataDir) {
    let writable =
      false;

    try {
      fs.mkdirSync(
        dataDir,
        {
          recursive: true,
        },
      );

      fs.accessSync(
        dataDir,
        fs.constants.R_OK |
          fs.constants.W_OK,
      );

      writable =
        true;
    } catch {
      writable =
        false;
    }

    checks.push({
      id:
        "data-dir:rw",
      ok:
        writable,
      required:
        true,
      message:
        writable
          ? "Persistent data directory is readable and writable."
          : "Persistent data directory is not readable and writable.",
    });

    for (
      const file
      of input.files
    ) {
      const fullPath =
        path.join(
          dataDir,
          file,
        );

      if (
        !fs.existsSync(
          fullPath,
        )
      ) {
        checks.push({
          id:
            `store:${file}`,
          ok:
            true,
          required:
            false,
          message:
            `${file} does not exist yet; a new store can be created.`,
        });

        continue;
      }

      let valid =
        false;

      try {
        JSON.parse(
          fs.readFileSync(
            fullPath,
            "utf8",
          ),
        );

        valid =
          true;
      } catch {
        valid =
          false;
      }

      checks.push({
        id:
          `store:${file}`,
        ok:
          valid,
        required:
          true,
        message:
          valid
            ? `${file} is readable JSON.`
            : `${file} is unreadable or invalid JSON.`,
      });
    }
  }

  return {
    ready:
      checks
        .filter(
          (check) =>
            check.required,
        )
        .every(
          (check) =>
            check.ok,
        ),
    checks,
  };
}
