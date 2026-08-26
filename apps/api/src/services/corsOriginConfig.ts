export type CorsOriginReadiness = {
  ready: boolean;
  allowedOrigins: string[];
  checks: Array<{
    id: string;
    ok: boolean;
    required: boolean;
    message: string;
  }>;
};

function normalizeOrigin(
  value: string | undefined,
): string | null {
  if (!value) return null;

  try {
    return new URL(value).origin;
  } catch {
    return null;
  }
}

export function resolveCorsOrigins(
  env: Record<string, string | undefined>,
): string[] {
  const origins = new Set<string>();

  const dashboard =
    normalizeOrigin(env.DASHBOARD_ORIGIN);

  if (dashboard) {
    origins.add(dashboard);
  }

  for (
    const value
    of env.SPORTSOS_CORS_ORIGINS?.split(",") ?? []
  ) {
    const origin =
      normalizeOrigin(value.trim());

    if (origin) {
      origins.add(origin);
    }
  }

  return [...origins];
}

export function evaluateCorsOriginReadiness(
  env: Record<string, string | undefined>,
): CorsOriginReadiness {
  const allowedOrigins =
    resolveCorsOrigins(env);

  const dashboard =
    normalizeOrigin(env.DASHBOARD_ORIGIN);

  const checks = [
    {
      id: "dashboard-origin:valid",
      ok: Boolean(dashboard),
      required: true,
      message:
        "DASHBOARD_ORIGIN must be a valid absolute origin.",
    },
    {
      id: "dashboard-origin:allowed",
      ok: Boolean(
        dashboard &&
        allowedOrigins.includes(dashboard),
      ),
      required: true,
      message:
        "Configured dashboard origin must be allowed by CORS.",
    },
    {
      id: "cors:wildcard-disabled",
      ok: !allowedOrigins.includes("*"),
      required: true,
      message:
        "Wildcard CORS origin is not permitted for credentialed production requests.",
    },
  ];

  return {
    ready:
      checks
        .filter((check) => check.required)
        .every((check) => check.ok),
    allowedOrigins,
    checks,
  };
}
