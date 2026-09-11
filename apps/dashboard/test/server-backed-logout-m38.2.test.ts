import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const shell = readFileSync(path.resolve(__dirname, "../components/AppShell.tsx"), "utf8");
const backend = readFileSync(path.resolve(__dirname, "../../api/src/routes/auth.ts"), "utf8");

describe("M38.2 server-backed logout", () => {
  it("sends the current refresh token to the authenticated logout route", () => {
    expect(shell).toContain("getStoredRefreshToken");
    expect(shell).toContain('authenticatedFetch<{ readonly success: boolean }>("/auth/logout"');
    expect(shell).toContain("JSON.stringify(refreshToken ? { refreshToken } : {})");
  });

  it("clears browser authentication even when server revocation cannot complete", () => {
    expect(shell).toContain("} catch {");
    expect(shell).toContain("} finally {");
    expect(shell).toContain("clearAuthentication()");
    expect(shell).toContain('router.replace("/login")');
    expect(shell).toContain("router.refresh()");
  });

  it("prevents duplicate interactive logout requests", () => {
    expect(shell).toContain("if (signingOut)");
    expect(shell).toContain("setSigningOut(true)");
    expect(shell).toContain("disabled={signingOut}");
  });

  it("matches the existing backend session-revocation contract", () => {
    expect(backend).toContain('app.post("/auth/logout", { preHandler: requireAuth }');
    expect(backend).toContain("await revokeAuthSession(identity.sessionId, identity.userId)");
    expect(backend).toContain("await revokeRefreshToken(parsed.data.refreshToken)");
  });
});
