export type ReleaseReadinessCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type ReleaseReadinessInput = {
  env: Record<string, string | undefined>;
};

export type ReleaseReadinessResult = {
  ready: boolean;
  checks: ReleaseReadinessCheck[];
};

function configured(
  value: string | undefined,
): boolean {
  return Boolean(
    value?.trim(),
  );
}

export function evaluateBroadcastReleaseReadiness(
  input: ReleaseReadinessInput,
): ReleaseReadinessResult {
  const env =
    input.env;

  const checks:
    ReleaseReadinessCheck[] =
    [];

  checks.push({
    id:
      "runtime:node-env",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV === "production"
        ? "API is running in production mode."
        : "API must run with NODE_ENV=production.",
  });

  checks.push({
    id:
      "runtime:api-port",
    ok:
      env.PORT ===
      "4001",
    required:
      true,
    message:
      env.PORT === "4001"
        ? "API runtime port is 4001."
        : "API runtime PORT must be 4001.",
  });

  checks.push({
    id:
      "runtime:host",
    ok:
      env.HOST ===
      "0.0.0.0",
    required:
      true,
    message:
      env.HOST === "0.0.0.0"
        ? "API binds to 0.0.0.0."
        : "API HOST must be 0.0.0.0.",
  });

  checks.push({
    id:
      "runtime:data-dir",
    ok:
      env.SPORTSOS_DATA_DIR ===
      "/app/data",
    required:
      true,
    message:
      env.SPORTSOS_DATA_DIR === "/app/data"
        ? "Persistent data directory is /app/data."
        : "SPORTSOS_DATA_DIR must be /app/data.",
  });

  checks.push({
    id:
      "runtime:dashboard-origin",
    ok:
      configured(
        env.DASHBOARD_ORIGIN,
      ),
    required:
      true,
    message:
      configured(env.DASHBOARD_ORIGIN)
        ? "Dashboard origin is configured."
        : "DASHBOARD_ORIGIN is missing.",
  });

  checks.push({
    id:
      "runtime:public-api-url",
    ok:
      configured(
        env.PUBLIC_API_URL,
      ),
    required:
      true,
    message:
      configured(env.PUBLIC_API_URL)
        ? "Public API URL is configured."
        : "PUBLIC_API_URL is missing.",
  });

  for (
    const name
    of [
      "MYSQL_HOST",
      "MYSQL_DATABASE",
      "MYSQL_USER",
      "MYSQL_PASSWORD",
      "MINIO_ENDPOINT",
      "MINIO_ACCESS_KEY",
      "MINIO_SECRET_KEY",
      "JWT_SECRET",
    ]
  ) {
    checks.push({
      id:
        `runtime:${name}`,
      ok:
        configured(
          env[name],
        ),
      required:
        true,
      message:
        configured(env[name])
          ? `${name} is configured.`
          : `${name} is missing.`,
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
