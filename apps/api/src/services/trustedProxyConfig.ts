export type TrustedProxyReadiness = {
  ready: boolean;
  configured: boolean;
  trustProxy: string[];
  forwardedHeaders: {
    proto: "x-forwarded-proto";
    host: "x-forwarded-host";
    for: "x-forwarded-for";
  };
  message: string;
};

const DEFAULT_TRUST_PROXY = [
  "loopback",
  "linklocal",
  "uniquelocal",
];

export function resolveTrustedProxyConfig(
  env:
    Record<string, string | undefined>,
): string[] {
  const raw =
    env.SPORTSOS_TRUST_PROXY?.trim();

  if (!raw) {
    return [
      ...DEFAULT_TRUST_PROXY,
    ];
  }

  return raw
    .split(",")
    .map(
      (value) =>
        value.trim(),
    )
    .filter(Boolean);
}

export function evaluateTrustedProxyReadiness(
  env:
    Record<string, string | undefined>,
): TrustedProxyReadiness {
  const trustProxy =
    resolveTrustedProxyConfig(
      env,
    );

  return {
    ready:
      trustProxy.length >
      0,
    configured:
      Boolean(
        env.SPORTSOS_TRUST_PROXY?.trim(),
      ),
    trustProxy,
    forwardedHeaders: {
      proto:
        "x-forwarded-proto",
      host:
        "x-forwarded-host",
      for:
        "x-forwarded-for",
    },
    message:
      env.SPORTSOS_TRUST_PROXY?.trim()
        ? "Explicit trusted proxy configuration is active."
        : "Using safe private-network defaults: loopback, linklocal, uniquelocal.",
  };
}
