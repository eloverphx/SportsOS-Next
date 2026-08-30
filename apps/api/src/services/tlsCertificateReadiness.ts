export type TlsCertificateReadiness = {
  ready: boolean;
  checks: Array<{
    id: string;
    ok: boolean;
    required: boolean;
    message: string;
  }>;
  targets: string[];
  minimumDaysRemaining: number;
};

function hostnameFromUrl(
  value: string | undefined,
): string | null {
  if (!value) return null;

  try {
    const url =
      new URL(value);

    if (
      url.protocol !==
      "https:"
    ) {
      return null;
    }

    return url.hostname;
  } catch {
    return null;
  }
}

export function evaluateTlsCertificateReadiness(
  env: Record<string, string | undefined>,
): TlsCertificateReadiness {
  const apiHost =
    hostnameFromUrl(
      env.PUBLIC_API_URL,
    );

  const dashboardHost =
    hostnameFromUrl(
      env.DASHBOARD_ORIGIN,
    );

  const targets =
    Array.from(
      new Set(
        [
          apiHost,
          dashboardHost,
        ].filter(
          (
            value,
          ): value is string =>
            Boolean(value),
        ),
      ),
    );

  const minimumDaysRemaining =
    Number(
      env.SPORTSOS_TLS_MIN_DAYS ??
      14,
    );

  const checks = [
    {
      id:
        "tls:api-host",
      ok:
        Boolean(apiHost),
      required:
        true,
      message:
        "PUBLIC_API_URL must be an https:// URL with a valid hostname.",
    },
    {
      id:
        "tls:dashboard-host",
      ok:
        Boolean(dashboardHost),
      required:
        true,
      message:
        "DASHBOARD_ORIGIN must be an https:// URL with a valid hostname.",
    },
    {
      id:
        "tls:min-days-valid",
      ok:
        Number.isFinite(
          minimumDaysRemaining,
        ) &&
        minimumDaysRemaining >=
          1,
      required:
        true,
      message:
        "SPORTSOS_TLS_MIN_DAYS must be at least 1.",
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
    checks,
    targets,
    minimumDaysRemaining,
  };
}
