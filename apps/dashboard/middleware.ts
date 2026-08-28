import {
  NextResponse,
  type NextRequest,
} from "next/server";

const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "object-src 'none'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data: https:",
  "style-src 'self' 'unsafe-inline'",
  "script-src 'self' 'unsafe-inline'",
  "connect-src 'self' https://api.crashthenet.online wss://api.crashthenet.online",
  "media-src 'self' blob:",
  "worker-src 'self' blob:",
  "manifest-src 'self'",
  "upgrade-insecure-requests",
].join("; ");

// SPORTSOS_M30_3_2_CONTENT_SECURITY_POLICY

const SECURITY_HEADERS = {
  "Content-Security-Policy":
    CONTENT_SECURITY_POLICY,
  "Cross-Origin-Opener-Policy":
    "same-origin",
  "Cross-Origin-Resource-Policy":
    "same-origin",
  "Permissions-Policy":
    "camera=(), microphone=(), geolocation=()",
  "Referrer-Policy":
    "no-referrer",
  "X-Content-Type-Options":
    "nosniff",
  "X-Frame-Options":
    "DENY",
} as const;

export function middleware(
  request: NextRequest,
) {
  const response =
    NextResponse.next();

  for (
    const [
      name,
      value,
    ]
    of Object.entries(
      SECURITY_HEADERS,
    )
  ) {
    response.headers.set(
      name,
      value,
    );
  }

  if (
    process.env.NODE_ENV ===
    "production"
  ) {
    response.headers.set(
      "Strict-Transport-Security",
      "max-age=31536000; includeSubDomains",
    );
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
