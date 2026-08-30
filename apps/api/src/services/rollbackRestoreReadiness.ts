import fs from "node:fs";
import path from "node:path";

export type RollbackRestoreCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type RollbackRestoreReadinessInput = {
  root: string;
  dataDir: string | null;
  backupDir: string | null;
};

export type RollbackRestoreReadinessResult = {
  ready: boolean;
  checks: RollbackRestoreCheck[];
};

export function evaluateRollbackRestoreReadiness(
  input: RollbackRestoreReadinessInput,
): RollbackRestoreReadinessResult {
  const checks:
    RollbackRestoreCheck[] =
    [];

  const composeFile =
    path.join(
      input.root,
      "docker-compose.yml",
    );

  const smokeScript =
    path.join(
      input.root,
      "scripts/release-smoke-test.sh",
    );

  checks.push({
    id:
      "rollback:compose-present",
    ok:
      fs.existsSync(
        composeFile,
      ),
    required:
      true,
    message:
      "docker-compose.yml must be present for rollback.",
  });

  checks.push({
    id:
      "rollback:smoke-test-present",
    ok:
      fs.existsSync(
        smokeScript,
      ),
    required:
      true,
    message:
      "Release smoke-test script must be present.",
  });

  const dataDir =
    input.dataDir?.trim() ??
    "";

  checks.push({
    id:
      "restore:data-dir-configured",
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
    let readable =
      false;

    try {
      fs.accessSync(
        dataDir,
        fs.constants.R_OK,
      );

      readable =
        true;
    } catch {
      readable =
        false;
    }

    checks.push({
      id:
        "restore:data-dir-readable",
      ok:
        readable,
      required:
        true,
      message:
        readable
          ? "Persistent data directory is readable."
          : "Persistent data directory is not readable.",
    });
  }

  const backupDir =
    input.backupDir?.trim() ??
    "";

  checks.push({
    id:
      "restore:backup-dir-configured",
    ok:
      Boolean(
        backupDir,
      ),
    required:
      true,
    message:
      backupDir
        ? `Backup directory is ${backupDir}.`
        : "Backup directory is not configured.",
  });

  if (backupDir) {
    let writable =
      false;

    try {
      fs.mkdirSync(
        backupDir,
        {
          recursive: true,
        },
      );

      fs.accessSync(
        backupDir,
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
        "restore:backup-dir-rw",
      ok:
        writable,
      required:
        true,
      message:
        writable
          ? "Backup directory is readable and writable."
          : "Backup directory is not readable and writable.",
    });
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
