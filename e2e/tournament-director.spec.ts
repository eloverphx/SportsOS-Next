import { expect, test, type Page, type Route } from "@playwright/test";

const director = {
  id: 9001,
  organizationId: 9,
  organizationName: "Prior Lake Hockey",
  firstName: "Tournament",
  lastName: "Director",
  email: "director@example.test",
  username: "director",
  role: "system_admin",
  permissions: [
    "game.read",
    "game.score",
    "scoreboard.read",
    "stream.read",
    "system.read",
  ],
};

function json(route: Route, body: unknown) {
  return route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify(body),
  });
}

async function installSession(page: Page) {
  await page.addInitScript((user) => {
    window.localStorage.setItem("sportsos_token", "e2e-director-token");
    window.localStorage.setItem("sportsos_user", JSON.stringify(user));
  }, director);
}

async function installRealtimeFixture(page: Page) {
  let namespaceConnected = false;

  await page.route("**/socket.io/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const transport = url.searchParams.get("transport");

    if (transport !== "polling") {
      return route.abort();
    }

    if (request.method() === "POST") {
      const body = request.postData() ?? "";
      if (body.includes("40")) namespaceConnected = true;

      return route.fulfill({
        status: 200,
        contentType: "text/plain; charset=UTF-8",
        body: "ok",
      });
    }

    if (!url.searchParams.has("sid")) {
      return route.fulfill({
        status: 200,
        contentType: "text/plain; charset=UTF-8",
        body:
          '0{"sid":"sportsos-director-e2e","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}',
      });
    }

    return route.fulfill({
      status: 200,
      contentType: "text/plain; charset=UTF-8",
      body: namespaceConnected ? '40{"sid":"sportsos-director-namespace"}' : "6",
    });
  });
}

test.describe("Tournament Director", () => {
  test("groups rinks and surfaces urgency, device, penalty, and engine attention", async ({
    page,
  }) => {
    const now = Date.now();
    const games = [
      {
        id: 1,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        seasonName: "2026 Tournament",
        homeTeamName: "Prior Lake Lakers",
        awayTeamName: "Edina Hornets",
        scheduledStart: new Date(now - 30 * 60_000).toISOString(),
        venue: "Rink 1",
        status: "LIVE",
        homeScore: 2,
        awayScore: 1,
        period: 2,
        clockRemainingMs: 482_000,
        clockRunning: false,
        clockStartedAt: null,
      },
      {
        id: 2,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        seasonName: "2026 Tournament",
        homeTeamName: "Lakeville North",
        awayTeamName: "Shakopee",
        scheduledStart: new Date(now + 10 * 60_000).toISOString(),
        venue: "Rink 1",
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        period: 1,
        clockRemainingMs: 1_200_000,
        clockRunning: false,
        clockStartedAt: null,
      },
      {
        id: 3,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        seasonName: "2026 Tournament",
        homeTeamName: "Burnsville",
        awayTeamName: "Chaska",
        scheduledStart: new Date(now - 10 * 60_000).toISOString(),
        venue: "Rink 2",
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        period: 1,
        clockRemainingMs: 1_200_000,
        clockRunning: false,
        clockStartedAt: null,
      },
    ];

    await installSession(page);
    await installRealtimeFixture(page);

    await page.route("**/auth/me", (route) => json(route, { user: director }));
    await page.route("**/games", (route) => json(route, { games }));
    await page.route("**/scoreboard-devices", (route) =>
      json(route, {
        devices: [
          {
            id: 501,
            organizationId: 9,
            organizationName: "Prior Lake Hockey",
            gameId: 1,
            gameLabel: "Prior Lake Lakers vs Edina Hornets",
            name: "Rink 1 Scoreboard",
            location: "Rink 1",
            status: "OFFLINE",
            lastSeenAt: new Date(now - 120_000).toISOString(),
          },
        ],
      }),
    );
    await page.route("**/system/game-engine", (route) =>
      json(route, {
        status: "attention",
        summary: {
          total: 3,
          healthy: 2,
          transitionPending: 0,
          operatorRequired: 1,
          warnings: 0,
        },
        games: [
          {
            gameId: 1,
            matchup: "Prior Lake Lakers vs Edina Hornets",
            state: "OPERATOR_REQUIRED",
            status: "LIVE",
            gamePhase: "REGULATION",
            period: 2,
            regulationPeriods: 3,
            clockRemainingMs: 482_000,
            clockRunning: false,
            intermissionRemainingMs: 0,
            intermissionRunning: false,
            actionRequired: "Confirm scorer table clock state",
            warnings: [],
          },
          {
            gameId: 2,
            matchup: "Lakeville North vs Shakopee",
            state: "HEALTHY",
            status: "SCHEDULED",
            gamePhase: "PREGAME",
            period: 1,
            regulationPeriods: 3,
            clockRemainingMs: 1_200_000,
            clockRunning: false,
            intermissionRemainingMs: 0,
            intermissionRunning: false,
            actionRequired: null,
            warnings: [],
          },
          {
            gameId: 3,
            matchup: "Burnsville vs Chaska",
            state: "HEALTHY",
            status: "SCHEDULED",
            gamePhase: "PREGAME",
            period: 1,
            regulationPeriods: 3,
            clockRemainingMs: 1_200_000,
            clockRunning: false,
            intermissionRemainingMs: 0,
            intermissionRunning: false,
            actionRequired: null,
            warnings: [],
          },
        ],
      }),
    );
    await page.route("**/games/1/penalties", (route) =>
      json(route, {
        penalties: [
          {
            id: 77,
            gameId: 1,
            side: "away",
            playerName: "Eddie Hornet",
            jerseyNumber: 22,
            infraction: "Hooking",
            remainingMs: 83_000,
            running: false,
            startedAt: null,
          },
        ],
      }),
    );

    await page.goto("/tournament-director");

    await expect(page.getByRole("heading", { name: "Tournament Director" })).toBeVisible();
    await expect(page.getByText("Realtime connected")).toBeVisible();

    const rink1 = page.getByRole("region", { name: "Rink 1" });
    const rink2 = page.getByRole("region", { name: "Rink 2" });

    await expect(rink1).toBeVisible();
    await expect(rink2).toBeVisible();
    await expect(rink1.getByText("2 games")).toBeVisible();
    await expect(rink1.getByText("Prior Lake Lakers")).toBeVisible();
    await expect(rink1.getByText("STARTING SOON")).toBeVisible();
    await expect(rink2.getByText("LATE START")).toBeVisible();

    await expect(rink1.getByText("Operator required")).toBeVisible();
    await expect(rink1.getByText("Confirm scorer table clock state")).toBeVisible();
    await expect(rink1.getByText("0/1 online")).toBeVisible();
    await expect(rink1.getByText("Hooking", { exact: false })).toBeVisible();

    await expect(
      rink1.getByRole("link", { name: "Open Scorekeeper" }).first(),
    ).toHaveAttribute("href", "/games/1/control");

    await page.getByPlaceholder("Team, rink, season…").fill("Burnsville");
    await expect(rink2).toBeVisible();
    await expect(rink1).toBeHidden();
  });
});

