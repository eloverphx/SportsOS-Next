export type SecretEnvironmentCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type SecretEnvironmentValidationResult = {
  ready: boolean;
  checks: SecretEnvironmentCheck[];
};

function isHttpUrl(
  value: string | undefined,
): boolean {
  if (!value) {
    return false;
  }

  try {
    const url =
      new URL(
        value,
      );

    return (
      url.protocol ===
        "http:" ||
      url.protocol ===
        "https:"
    );
  } catch {
    return false;
  }
}

function isStrongEnoughSecret(
  value: string | undefined,
  minLength: number,
): boolean {
  if (!value) {
    return false;
  }

  const trimmed =
    value.trim();

  if (
    trimmed.length <
    minLength
  ) {
    return false;
  }

  const lowered =
    trimmed.toLowerCase();

  const forbidden = [
    "password",
    "changeme",
    "change-me",
    "secret",
    "default",
    "replace-with",
  ];

  return !forbidden.some(
    (token) =>
      lowered.includes(
        token,
      ),
  );
}

export function validateSecretEnvironment(
  env:
    Record<string, string | undefined>,
): SecretEnvironmentValidationResult {
  const checks:
    SecretEnvironmentCheck[] =
    [];

  checks.push({
    id:
      "node-env:production",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV ===
      "production"
        ? "NODE_ENV is production."
        : "NODE_ENV must be production.",
  });

  checks.push({
    id:
      "jwt:quality",
    ok:
      isStrongEnoughSecret(
        env.JWT_SECRET,
        32,
      ),
    required:
      true,
    message:
      "JWT secret must be at least 32 characters and must not use an obvious placeholder/default value.",
  });

  checks.push({
    id:
      "mysql-password:quality",
    ok:
      isStrongEnoughSecret(
        env.MYSQL_PASSWORD,
        12,
      ),
    required:
      true,
    message:
      "MySQL password must be at least 12 characters and must not use an obvious placeholder/default value.",
  });

  checks.push({
    id:
      "minio-password:quality",
    ok:
      isStrongEnoughSecret(
        env.MINIO_SECRET_KEY,
        12,
      ),
    required:
      true,
    message:
      "MinIO root password must be at least 12 characters and must not use an obvious placeholder/default value.",
  });

  checks.push({
    id:
      "dashboard-url:valid",
    ok:
      isHttpUrl(
        env.DASHBOARD_ORIGIN,
      ),
    required:
      true,
    message:
      "DASHBOARD_ORIGIN must be a valid http(s) URL.",
  });

  checks.push({
    id:
      "api-url:valid",
    ok:
      isHttpUrl(
        env.PUBLIC_API_URL,
      ),
    required:
      true,
    message:
      "PUBLIC_API_URL must be a valid http(s) URL.",
  });

  checks.push({
    id:
      "mysql-user:not-root",
    ok:
      Boolean(
        env.MYSQL_USER &&
        env.MYSQL_USER.trim() &&
        env.MYSQL_USER.trim() !==
          "root",
      ),
    required:
      true,
    message:
      "SportsOS should use a dedicated MySQL user instead of root.",
  });

  checks.push({
    id:
      "minio-user:configured",
    ok:
      Boolean(
        env.MINIO_ACCESS_KEY?.trim(),
      ),
    required:
      true,
    message:
      "MINIO_ACCESS_KEY must be configured.",
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
    checks,
  };
}
