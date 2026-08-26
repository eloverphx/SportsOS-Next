export type PublicExposureReadiness = {
  ready: boolean;
  intendedPublicPaths: string[];
  blockedPatterns: string[];
  checks: Array<{
    id: string;
    ok: boolean;
    required: boolean;
    message: string;
  }>;
};

export function evaluatePublicExposureReadiness(
  env: Record<string, string | undefined>,
): PublicExposureReadiness {
  const intendedPublicPaths = [
    "/",
    "/api/",
    "/api/health",
    "/socket.io/",
  ];

  const blockedPatterns = [
    "/admin",
    "/debug",
    "/internal",
    "/metrics",
    "/docs",
    "/openapi",
    "/swagger",
  ];

  const checks = [
    {
      id: "runtime:production",
      ok: env.NODE_ENV === "production",
      required: true,
      message:
        "Public exposure audit requires production runtime.",
    },
    {
      id: "api:public-url-configured",
      ok: Boolean(env.PUBLIC_API_URL),
      required: true,
      message:
        "PUBLIC_API_URL must be configured.",
    },
    {
      id: "dashboard:origin-configured",
      ok: Boolean(env.DASHBOARD_ORIGIN),
      required: true,
      message:
        "DASHBOARD_ORIGIN must be configured.",
    },
  ];

  return {
    ready:
      checks
        .filter((check) => check.required)
        .every((check) => check.ok),
    intendedPublicPaths,
    blockedPatterns,
    checks,
  };
}
