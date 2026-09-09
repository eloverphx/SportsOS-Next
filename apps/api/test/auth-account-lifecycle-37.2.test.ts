import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const apiRoot = resolve(testDir, "..");

function source(path: string): string {
  return readFileSync(resolve(apiRoot, path), "utf8");
}

const migrations = source("src/infrastructure/streaming-foundation-migrations.ts");
const authRoutes = source("src/routes/auth.ts");
const memberRoutes = source("src/routes/organization-members.ts");
const sessionRepository = source("src/modules/auth/session-repository.ts");
const authorization = source("src/modules/auth/authorization.ts");
const authLibrary = source("src/lib/auth.ts");

describe("Milestone 37.2 account approval and durable sessions", () => {
  it("preserves existing users as active while supporting pending signup accounts", () => {
    expect(migrations).toContain(
      "ENUM('PENDING','ACTIVE','SUSPENDED','REJECTED') NOT NULL DEFAULT 'ACTIVE'",
    );
    expect(authRoutes).toContain('app.post("/auth/signup"');
    expect(authRoutes).toContain('"PENDING_APPROVAL"');
    expect(authRoutes).toContain("Account is pending administrator approval");
  });

  it("requires existing organization-member authority to approve or reject signup", () => {
    expect(memberRoutes).toContain('"/organizations/:organizationId/members/pending"');
    expect(memberRoutes).toContain('"/organizations/:organizationId/members/:userId/approve"');
    expect(memberRoutes).toContain('"/organizations/:organizationId/members/:userId/reject"');
    expect(memberRoutes).toContain("PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE");
  });

  it("stores only hashed refresh-token material and supports rotation and revocation", () => {
    expect(sessionRepository).toContain("refresh_token_hash");
    expect(sessionRepository).toContain("hashRefreshToken(refreshToken)");
    expect(sessionRepository).toContain("rotateAuthSession");
    expect(sessionRepository).toContain("revokeAuthSession");
    expect(sessionRepository).not.toMatch(/INSERT INTO auth_sessions[^]*refresh_token\s*[,)]/);
  });

  it("enforces active account status for authenticated and permission-protected requests", () => {
    expect(authLibrary).toContain("await assertActiveAccount");
    expect(authorization).toContain("await assertActiveAccount");
  });

  it("preserves the existing access-token response while adding refresh sessions", () => {
    expect(authRoutes).toContain("return {\n      token,");
    expect(authRoutes).toContain("refreshToken: session.refreshToken");
    expect(authRoutes).toContain('{ expiresIn: "8h" }');
  });
});
