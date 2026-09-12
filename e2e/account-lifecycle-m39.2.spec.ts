import { expect, test, type BrowserContext, type Page } from "@playwright/test";

const organization = {
  id: 7,
  name: "Prior Lake Lakers",
} as const;

const pendingMember = {
  id: 71,
  organizationId: organization.id,
  firstName: "Casey",
  lastName: "Tester",
  email: "casey.tester@example.test",
  username: "caseytester",
  role: "viewer",
  createdAt: "2026-09-12T00:00:00.000Z",
} as const;

const adminUser = {
  id: 1,
  organizationId: organization.id,
  organizationName: organization.name,
  firstName: "Admin",
  lastName: "Operator",
  email: "admin@example.test",
  username: "admin",
  role: "organization_admin",
  permissions: ["organization.members.manage"],
} as const;

const approvedUser = {
  id: pendingMember.id,
  organizationId: organization.id,
  organizationName: organization.name,
  firstName: pendingMember.firstName,
  lastName: pendingMember.lastName,
  email: pendingMember.email,
  username: pendingMember.username,
  role: "viewer",
  permissions: [],
} as const;

async function seedAuthentication(
  context: BrowserContext,
  token: string,
  refreshToken: string,
  user: object,
): Promise<void> {
  await context.addInitScript(
    ({ accessToken, durableRefreshToken, serializedUser }) => {
      window.localStorage.setItem("sportsos_token", accessToken);
      window.localStorage.setItem("sportsos_refresh_token", durableRefreshToken);
      window.localStorage.setItem("sportsos_user", serializedUser);
    },
    {
      accessToken: token,
      durableRefreshToken: refreshToken,
      serializedUser: JSON.stringify(user),
    },
  );
}

async function mockDashboard(page: Page): Promise<void> {
  await page.route("**/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ user: approvedUser }),
    });
  });

  await page.route("**/dashboard/stats", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        organizations: 1,
        teams: 0,
        players: 0,
        activeGames: 0,
        liveStreams: 0,
      }),
    });
  });

  await page.route("**/audit/recent", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ events: [] }),
    });
  });
}

test("M39.2 account acceptance: signup, approve, login, and revoke session", async ({
  browser,
}) => {
  let approved = false;
  let signupPayload: Record<string, unknown> | null = null;
  let approvalRequestSeen = false;
  let logoutPayload: Record<string, unknown> | null = null;

  const signupContext = await browser.newContext();
  const signupPage = await signupContext.newPage();

  await signupPage.route("**/auth/signup-organizations", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ organizations: [organization] }),
    });
  });

  await signupPage.route("**/auth/signup", async (route) => {
    signupPayload = route.request().postDataJSON() as Record<string, unknown>;

    await route.fulfill({
      status: 202,
      contentType: "application/json",
      body: JSON.stringify({
        success: true,
        status: "PENDING_APPROVAL",
        message: "Your account request is awaiting administrator approval.",
      }),
    });
  });

  await signupPage.goto("/signup");

  await expect(signupPage.getByRole("heading", { name: "Request access" })).toBeVisible();
  await signupPage.getByLabel("Organization").selectOption(String(organization.id));
  await signupPage.getByPlaceholder("First name").fill(pendingMember.firstName);
  await signupPage.getByPlaceholder("Last name").fill(pendingMember.lastName);
  await signupPage.getByPlaceholder("Email").fill(pendingMember.email);
  await signupPage.getByPlaceholder("Username").fill(pendingMember.username);
  await signupPage.getByPlaceholder("Password").fill("SportsOS-Test-Password-39");
  await signupPage.getByRole("button", { name: "Request access" }).click();

  await expect(
    signupPage.getByText("Your account request is awaiting administrator approval."),
  ).toBeVisible();

  expect(signupPayload).toMatchObject({
    organizationId: organization.id,
    firstName: pendingMember.firstName,
    lastName: pendingMember.lastName,
    email: pendingMember.email,
    username: pendingMember.username,
  });

  await signupContext.close();

  const adminContext = await browser.newContext();
  await seedAuthentication(adminContext, "admin-access-token", "admin-refresh-token", adminUser);
  const adminPage = await adminContext.newPage();
  await adminPage.route("**/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        user: adminUser,
      }),
    });
  });
  await adminPage.route("**/organizations/7/members**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());

    if (request.method() === "GET" && url.pathname.endsWith("/members/pending")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          members: approved ? [] : [pendingMember],
        }),
      });
      return;
    }

    if (
      request.method() === "POST" &&
      url.pathname.endsWith(`/members/${pendingMember.id}/approve`)
    ) {
      approvalRequestSeen = true;
      approved = true;

      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          success: true,
          status: "ACTIVE",
        }),
      });
      return;
    }

    if (request.method() === "GET" && url.pathname.endsWith("/members")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          members: approved ? [approvedUser] : [],
        }),
      });
      return;
    }

    await route.fallback();
  });

  await adminPage.goto("/users");

  await expect(adminPage.getByRole("heading", { name: "Pending approvals" })).toBeVisible();
  await expect(
    adminPage.getByRole("heading", {
      name: `${pendingMember.firstName} ${pendingMember.lastName}`,
    }),
  ).toBeVisible();

  await adminPage.getByRole("button", { name: "Approve" }).click();

  await expect(adminPage.getByText("No accounts are awaiting approval.")).toBeVisible();
  expect(approvalRequestSeen).toBe(true);

  await adminContext.close();

  const memberContext = await browser.newContext();
  const memberPage = await memberContext.newPage();

  await memberPage.route("**/auth/login", async (route) => {
    const request = route.request();
    const body = request.postDataJSON() as Record<string, unknown>;

    expect(body).toEqual({
      identifier: pendingMember.username,
      password: "SportsOS-Test-Password-39",
    });

    expect(approved).toBe(true);

    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        token: "member-access-token",
        refreshToken: "member-refresh-token",
        session: {
          id: "session-m39-2",
          expiresAt: "2026-10-12T00:00:00.000Z",
        },
        user: approvedUser,
      }),
    });
  });

  await mockDashboard(memberPage);

  await memberPage.goto("/login");

  await expect(memberPage.getByRole("heading", { name: "Sign in" })).toBeVisible();

  await memberPage.getByPlaceholder("Username or email").fill(pendingMember.username);

  await memberPage.getByPlaceholder("Password").fill("SportsOS-Test-Password-39");

  await memberPage.getByRole("button", { name: "Sign in" }).click();
  await memberPage.getByPlaceholder("Username or email").fill(pendingMember.username);
  await memberPage.getByPlaceholder("Password").fill("SportsOS-Test-Password-39");
  await Promise.all([
    memberPage.waitForURL(/\/dashboard$/),
    memberPage.getByPlaceholder("Password").press("Enter"),
  ]);

  await expect(memberPage).toHaveURL(/\/dashboard$/);
  await expect(
    memberPage.getByRole("heading", { name: `Welcome, ${pendingMember.firstName}` }),
  ).toBeVisible();

  const storedSession = await memberPage.evaluate(() => ({
    token: window.localStorage.getItem("sportsos_token"),
    refreshToken: window.localStorage.getItem("sportsos_refresh_token"),
    user: JSON.parse(window.localStorage.getItem("sportsos_user") ?? "null"),
  }));

  expect(storedSession.token).toBe("member-access-token");
  expect(storedSession.refreshToken).toBe("member-refresh-token");
  expect(storedSession.user).toMatchObject({
    id: pendingMember.id,
    username: pendingMember.username,
  });

  await memberPage.route("**/auth/logout", async (route) => {
    logoutPayload = route.request().postDataJSON() as Record<string, unknown>;

    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ success: true }),
    });
  });

  await memberPage.getByRole("button", { name: "Sign out" }).click();

  await expect(memberPage).toHaveURL(/\/login$/);
  expect(logoutPayload).toEqual({
    refreshToken: "member-refresh-token",
  });

  const clearedSession = await memberPage.evaluate(() => ({
    token: window.localStorage.getItem("sportsos_token"),
    refreshToken: window.localStorage.getItem("sportsos_refresh_token"),
    user: window.localStorage.getItem("sportsos_user"),
  }));

  expect(clearedSession).toEqual({
    token: null,
    refreshToken: null,
    user: null,
  });

  await memberContext.close();
});
