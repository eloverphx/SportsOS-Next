import { NextResponse, type NextRequest } from "next/server";
import { buildDashboardContentSecurityPolicy } from "./lib/contentSecurityPolicy";

// SPORTSOS_M30_3_2_CONTENT_SECURITY_POLICY

const SECURITY_HEADERS = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
} as const;

export function middleware(request: NextRequest) {
  const response = NextResponse.next();

  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    response.headers.set(name, value);
  }

  response.headers.set("Content-Security-Policy", buildDashboardContentSecurityPolicy(process.env));

  if (process.env.NODE_ENV === "production") {
    response.headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
