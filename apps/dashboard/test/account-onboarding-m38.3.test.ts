import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function source(relativePath: string): string {
  return readFileSync(path.resolve(__dirname, relativePath), "utf8");
}

const authRoute = source("../../api/src/routes/auth.ts");
const accountRepository = source("../../api/src/modules/auth/account-repository.ts");
const signup = source("../app/signup/page.tsx");
const login = source("../app/login/page.tsx");
const users = source("../app/users/page.tsx");

describe("M38.3 account onboarding workflow", () => {
  it("publishes only active organizations for signup selection", () => {
    expect(authRoute).toContain('app.get("/auth/signup-organizations"');
    expect(accountRepository).toContain("export async function listSignupOrganizations");
    expect(accountRepository).toContain("WHERE active = TRUE");
    expect(accountRepository).toContain("ORDER BY name, id");
  });

  it("provides a public signup page using the existing pending-account contract", () => {
    expect(signup).toContain("fetch(`${getApiUrl()}/auth/signup-organizations`)");
    expect(signup).toContain("fetch(`${getApiUrl()}/auth/signup`");
    expect(signup).toContain("organizationId: Number(organizationId)");
    expect(signup).toContain('status: "PENDING_APPROVAL"');
    expect(login).toContain('<Link href="/signup">Request access</Link>');
  });

  it("loads pending members into the existing admin users workflow", () => {
    expect(users).toContain("`/organizations/${user.organizationId}/members/pending`");
    expect(users).toContain("<h2>Pending approvals</h2>");
  });

  it("supports approve and reject decisions through the existing backend routes", () => {
    expect(users).toContain('decision: "approve" | "reject"');
    expect(users).toContain(
      "`/organizations/${currentUser.organizationId}/members/${member.id}/${decision}`",
    );
    expect(users).toContain('void decidePendingMember(member, "approve")');
    expect(users).toContain('void decidePendingMember(member, "reject")');
  });
});
