export type CredentialRotationTarget =
  | "JWT_SECRET"
  | "MYSQL_PASSWORD"
  | "MINIO_SECRET_KEY";

export type CredentialRotationCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type CredentialRotationReadinessInput = {
  env: Record<string, string | undefined>;
  rollbackReady: boolean;
  dataMigrationReady: boolean;
};

export type CredentialRotationReadinessResult = {
  ready: boolean;
  targets: CredentialRotationTarget[];
  checks: CredentialRotationCheck[];
};

const TARGETS: CredentialRotationTarget[] = [
  "JWT_SECRET",
  "MYSQL_PASSWORD",
  "MINIO_SECRET_KEY",
];

function configured(
  value: string | undefined,
): boolean {
  return Boolean(
    value?.trim(),
  );
}

export function evaluateCredentialRotationReadiness(
  input: CredentialRotationReadinessInput,
): CredentialRotationReadinessResult {
  const checks: CredentialRotationCheck[] = [];

  checks.push({
    id: "rollback:ready",
    ok: input.rollbackReady,
    required: true,
    message:
      input.rollbackReady
        ? "Rollback / restore prerequisites are ready."
        : "Rollback / restore prerequisites are not ready.",
  });

  checks.push({
    id: "migration:ready",
    ok: input.dataMigrationReady,
    required: true,
    message:
      input.dataMigrationReady
        ? "Database and persistent-data readiness checks pass."
        : "Database or persistent-data readiness checks are not ready.",
  });

  for (const target of TARGETS) {
    checks.push({
      id: `current:${target}`,
      ok: configured(input.env[target]),
      required: true,
      message:
        configured(input.env[target])
          ? `${target} is currently configured.`
          : `${target} is missing.`,
    });
  }

  checks.push({
    id: "mysql:dedicated-user",
    ok:
      Boolean(
        input.env.MYSQL_USER?.trim(),
      ) &&
      input.env.MYSQL_USER?.trim() !==
        "root",
    required: true,
    message:
      "MySQL credential rotation requires a dedicated non-root SportsOS user.",
  });

  checks.push({
    id: "minio:access-key-present",
    ok:
      configured(
        input.env.MINIO_ACCESS_KEY,
      ),
    required: true,
    message:
      "MinIO credential rotation requires the current access key.",
  });

  checks.push({
    id: "runtime:data-dir",
    ok:
      input.env.SPORTSOS_DATA_DIR ===
      "/app/data",
    required: true,
    message:
      "Persistent SportsOS data must be mounted at /app/data before credential rotation.",
  });

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
    targets:
      [...TARGETS],
    checks,
  };
}
