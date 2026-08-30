export type ExternalHealthTarget = {
  id: "dashboard" | "api-health";
  url: string | null;
  required: boolean;
};

export type ExternalHealthReadiness = {
  ready: boolean;
  targets: ExternalHealthTarget[];
  checks: Array<{
    id: string;
    ok: boolean;
    required: boolean;
    message: string;
  }>;
};

function normalizeUrl(
  value: string | undefined,
): URL | null {
  if (!value) return null;

  try {
    return new URL(value);
  } catch {
    return null;
  }
}

export function evaluateExternalHealthReadiness(
  env: Record<string, string | undefined>,
): ExternalHealthReadiness {
  const api =
    normalizeUrl(
      env.PUBLIC_API_URL,
    );

  const dashboard =
    normalizeUrl(
      env.DASHBOARD_ORIGIN,
    );

  const apiHealth =
    api
      ? new URL(
          api.pathname.endsWith("/api")
            ? `${api.origin}${api.pathname}/health`
            : `${api.origin}/api/health`,
        ).toString()
      : null;

  const dashboardUrl =
    dashboard?.toString() ??
    null;

  const targets: ExternalHealthTarget[] = [
    {
      id:
        "dashboard",
      url:
        dashboardUrl,
      required:
        true,
    },
    {
      id:
        "api-health",
      url:
        apiHealth,
      required:
        true,
    },
  ];

  const checks = [
    {
      id:
        "dashboard:https",
      ok:
        dashboard?.protocol ===
        "https:",
      required:
        true,
      message:
        "Dashboard external URL must use HTTPS.",
    },
    {
      id:
        "api:https",
      ok:
        api?.protocol ===
        "https:",
      required:
        true,
      message:
        "API external URL must use HTTPS.",
    },
    {
      id:
        "targets:resolved",
      ok:
        targets.every(
          (target) =>
            Boolean(
              target.url,
            ),
        ),
      required:
        true,
      message:
        "External dashboard and API-health targets must resolve from configuration.",
    },
  ];

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
    targets,
    checks,
  };
}
