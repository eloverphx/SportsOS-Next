const DEFAULT_PUBLIC_API_URL = "https://api.crashthenet.online";

interface DashboardCspEnvironment {
  readonly NODE_ENV?: string;
  readonly NEXT_PUBLIC_API_URL?: string;
}

function configuredApiUrl(value?: string): URL {
  const candidate = value?.trim() || DEFAULT_PUBLIC_API_URL;

  try {
    return new URL(candidate);
  } catch {
    return new URL(DEFAULT_PUBLIC_API_URL);
  }
}

function websocketOrigin(apiUrl: URL): string | null {
  if (apiUrl.protocol !== "http:" && apiUrl.protocol !== "https:") {
    return null;
  }

  const websocketUrl = new URL(apiUrl.origin);
  websocketUrl.protocol = apiUrl.protocol === "https:" ? "wss:" : "ws:";

  return websocketUrl.origin;
}

export function buildDashboardContentSecurityPolicy(
  env: DashboardCspEnvironment = process.env,
): string {
  const apiUrl = configuredApiUrl(env.NEXT_PUBLIC_API_URL);
  const socketOrigin = websocketOrigin(apiUrl);

  const connectSources = new Set<string>([
    "'self'",
    apiUrl.origin,
    ...(socketOrigin ? [socketOrigin] : []),
  ]);

  const scriptSources = ["'self'", "'unsafe-inline'"];

  // Next dev relies on eval-style source transforms. Keep that permission
  // development-only; CI browser smoke tests run the production server.
  if (env.NODE_ENV !== "production") {
    scriptSources.push("'unsafe-eval'");
  }

  const directives = [
    "default-src 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data: https:",
    "style-src 'self' 'unsafe-inline'",
    `script-src ${scriptSources.join(" ")}`,
    `connect-src ${Array.from(connectSources).join(" ")}`,
    "media-src 'self' blob:",
    "worker-src 'self' blob:",
    "manifest-src 'self'",
  ];

  // Only force insecure requests to HTTPS when the configured production API
  // itself is HTTPS. CI intentionally exercises a loopback HTTP API origin.
  if (env.NODE_ENV === "production" && apiUrl.protocol === "https:") {
    directives.push("upgrade-insecure-requests");
  }

  return directives.join("; ");
}
