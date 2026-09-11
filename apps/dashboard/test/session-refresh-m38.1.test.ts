import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function source(relativePath: string): string {
  return readFileSync(path.resolve(__dirname, relativePath), "utf8");
}

const auth = source("../lib/auth.ts");
const refresh = source("../lib/session-refresh.ts");
const api = source("../lib/api.ts");
const authenticatedApi = source("../lib/authenticated-api.ts");
const login = source("../app/login/page.tsx");

describe("M38.1 dashboard refresh-session lifecycle", () => {
  it("persists and clears the rotated refresh token with the access session", () => {
    expect(auth).toContain('AUTH_REFRESH_TOKEN_KEY = "sportsos_refresh_token"');
    expect(auth).toContain("getStoredRefreshToken()");
    expect(auth).toContain("window.localStorage.setItem(AUTH_REFRESH_TOKEN_KEY, refreshToken)");
    expect(auth).toContain("window.localStorage.removeItem(AUTH_REFRESH_TOKEN_KEY)");
  });

  it("accepts the durable backend login response", () => {
    expect(auth).toContain("readonly refreshToken: string");
    expect(auth).toContain("readonly expiresAt: string");
    expect(login).toContain("!login.refreshToken");
    expect(login).toContain("storeAuthentication(login.token, login.refreshToken, login.user)");
  });

  it("single-flights rotating refresh requests", () => {
    expect(refresh).toContain("let refreshPromise: Promise<string> | null = null");
    expect(refresh).toContain("fetch(`${getApiUrl()}/auth/refresh`");
    expect(refresh).toContain("body: JSON.stringify({ refreshToken })");
    expect(refresh).toContain("refreshPromise = rotateSession().finally");
    expect(refresh).toContain("storeAuthentication(body.token, body.refreshToken, body.user)");
  });

  it("retries the legacy api helper once after a 401", () => {
    expect(api).toContain("if (response.status === 401)");
    expect(api).toContain("const refreshedToken = await refreshAuthentication()");
    expect(api).toContain("response = await fetchApi(path, options, refreshedToken)");
  });

  it("retries authenticatedFetch once after a 401", () => {
    expect(authenticatedApi).toContain("if (response.status === 401)");
    expect(authenticatedApi).toContain("const refreshedToken = await refreshAuthentication()");
    expect(authenticatedApi).toContain("response = await request(path, init, refreshedToken)");
  });
});
