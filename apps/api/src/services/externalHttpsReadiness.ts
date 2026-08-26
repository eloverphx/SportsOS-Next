export type ExternalHttpsCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type ExternalHttpsReadinessResult = {
  ready: boolean;
  checks: ExternalHttpsCheck[];
  expectations: {
    tlsTermination: "external-reverse-proxy";
    forwardedProtoRequired: boolean;
    forwardedHostRecommended: boolean;
    directContainerTlsRequired: boolean;
  };
};

function isHttpsUrl(
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

    return url.protocol ===
      "https:";
  } catch {
    return false;
  }
}

export function evaluateExternalHttpsReadiness(
  env:
    Record<string, string | undefined>,
): ExternalHttpsReadinessResult {
  const checks:
    ExternalHttpsCheck[] =
    [];

  checks.push({
    id:
      "runtime:production",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV ===
      "production"
        ? "Runtime is production."
        : "Runtime must be production.",
  });

  checks.push({
    id:
      "public-api:https",
    ok:
      isHttpsUrl(
        env.PUBLIC_API_URL,
      ),
    required:
      true,
    message:
      "PUBLIC_API_URL must use https:// for production external deployment.",
  });

  checks.push({
    id:
      "dashboard-origin:https",
    ok:
      isHttpsUrl(
        env.DASHBOARD_ORIGIN,
      ),
    required:
      true,
    message:
      "DASHBOARD_ORIGIN must use https:// for production external deployment.",
  });

  checks.push({
    id:
      "runtime:host-bind",
    ok:
      env.HOST ===
      "0.0.0.0",
    required:
      true,
    message:
      "API should bind to 0.0.0.0 behind the reverse proxy.",
  });

  checks.push({
    id:
      "transport:hsts-enabled",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      "Production runtime enables HSTS at the API response layer.",
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
    expectations: {
      tlsTermination:
        "external-reverse-proxy",
      forwardedProtoRequired:
        true,
      forwardedHostRecommended:
        true,
      directContainerTlsRequired:
        false,
    },
  };
}
