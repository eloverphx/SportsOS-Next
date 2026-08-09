import { expect, test, type Page, type Route } from "@playwright/test";

const director = {
  id: 9010,
  organizationId: 9,
  organizationName: "Prior Lake Hockey",
  firstName: "Tournament",
  lastName: "Director",
  email: "director-610@example.test",
  username: "director610",
  role: "system_admin",
  permissions: [
    "game.read",
    "game.manage",
    "game.score",
    "scoreboard.read",
    "scoreboard.manage",
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
    window.localStorage.setItem("sportsos_token", "e2e-director-610-token");
    window.localStorage.setItem("sportsos_user", JSON.stringify(user));
  }, director);
}

async function installRealtimeFixture(page: Page) {
  let namespaceConnected = false;

  await page.route("**/socket.io/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());

    if (url.searchParams.get("transport") !== "polling") {
      return route.abort();
    }

    if (request.method() === "POST") {
      if ((request.postData() ?? "").includes("40")) namespaceConnected = true;

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
          '0{"sid":"sportsos-610-e2e","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}',
      });
    }

    return route.fulfill({
      status: 200,
      contentType: "text/plain; charset=UTF-8",
      body: namespaceConnected ? '40{"sid":"sportsos-610-namespace"}' : "6",
    });
  });
}

test.describe("Tournament Operations 6.10", () => {
  test("director can move through attention, focus, timeline, and scheduling workflow", async ({
    page,
  }) => {
    const now = Date.now();

    const games = [
      {
        id: 101,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        seasonId: 1,
        seasonName: "2026 Tournament",
        homeTeamId: 10,
        homeTeamName: "Prior Lake Lakers",
        homeExternalName: null,
        awayTeamId: 20,
        awayTeamName: "Edina Hornets",
        awayExternalName: null,
        scheduledStart: new Date(now - 30 * 60_000).toISOString(),
        timezone: "America/Chicago",
        venue: "Rink 1",
        status: "LIVE",
        homeScore: 2,
        awayScore: 1,
        period: 2,
        clockRemainingMs: 482_000,
        clockRunning: false,
        clockStartedAt: null,
        regulationPeriods: 3,
        regulationPeriodLengthMs: 20 * 60_000,
        intermissionLengthMs: 10 * 60_000,
        overtimeEnabled: true,
        overtimeLengthMs: 5 * 60_000,
        notes: null,
      },
      {
        id: 102,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        seasonId: 1,
        seasonName: "2026 Tournament",
        homeTeamId: 30,
        homeTeamName: "Lakeville North",
        homeExternalName: null,
        awayTeamId: 40,
        awayTeamName: "Shakopee",
        awayExternalName: null,
        scheduledStart: new Date(now + 10 * 60_000).toISOString(),
        timezone: "America/Chicago",
        venue: "Rink 1",
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        period: 1,
        clockRemainingMs: 1_200_000,
        clockRunning: false,
        clockStartedAt: null,
        regulationPeriods: 3,
        regulationPeriodLengthMs: 20 * 60_000,
        intermissionLengthMs: 10 * 60_000,
        overtimeEnabled: false,
        overtimeLengthMs: 0,
        notes: null,
      },
      {
        id: 103,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        seasonId: 1,
        seasonName: "2026 Tournament",
        homeTeamId: 50,
        homeTeamName: "Burnsville",
        homeExternalName: null,
        awayTeamId: 60,
        awayTeamName: "Chaska",
        awayExternalName: null,
        scheduledStart: new Date(now - 10 * 60_000).toISOString(),
        timezone: "America/Chicago",
        venue: "Rink 2",
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        period: 1,
        clockRemainingMs: 1_200_000,
        clockRunning: false,
        clockStartedAt: null,
        regulationPeriods: 3,
        regulationPeriodLengthMs: 20 * 60_000,
        intermissionLengthMs: 10 * 60_000,
        overtimeEnabled: false,
        overtimeLengthMs: 0,
        notes: null,
      },
    ];

    const devices = [
      {
        id: 501,
        organizationId: 9,
        organizationName: "Prior Lake Hockey",
        gameId: 101,
        gameLabel: "Prior Lake Lakers vs Edina Hornets",
        name: "Rink 1 Scoreboard",
        location: "Rink 1",
        status: "OFFLINE",
        lastSeenAt: null,
      },
    ];

    await installSession(page);
    await installRealtimeFixture(page);

    await page.route("**/auth/me", (route) =>
      json(route, { user: director }),
    );

    await page.route("**/games", (route) =>
      json(route, { games }),
    );

    await page.route("**/scoreboard-devices", (route) =>
      json(route, { devices }),
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
            gameId: 101,
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
            actionRequired: "Confirm period transition",
            warnings: [],
          },
          {
            gameId: 102,
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
            gameId: 103,
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

    await page.route("**/games/101/penalties", (route) =>
      json(route, { penalties: [] }),
    );

    await page.route("**/games/102/penalties", (route) =>
      json(route, { penalties: [] }),
    );

    await page.route("**/games/103/penalties", (route) =>
      json(route, { penalties: [] }),
    );

    await page.route("**/games/101", (route) =>
      json(route, { game: games[0] }),
    );

    await page.route("**/games/102", (route) =>
      json(route, { game: games[1] }),
    );

    await page.route("**/games/103", (route) =>
      json(route, { game: games[2] }),
    );

    await page.goto("/tournament-director");

    await expect(
      page.getByRole("heading", { name: "Tournament Director" }),
    ).toBeVisible();

    const workflow = page.getByTestId("tournament-workflow-nav");
    await expect(workflow).toBeVisible();

    const workflowLinks = page.getByTestId("tournament-workflow-links");
    await expect(workflowLinks).toBeVisible();

    await expect(page.getByTestId("workflow-link-attention")).toHaveAttribute(
      "href",
      "#director-attention",
    );
    await expect(page.getByTestId("workflow-link-focus")).toHaveAttribute(
      "href",
      "#director-focus",
    );
    await expect(page.getByTestId("workflow-link-timeline")).toHaveAttribute(
      "href",
      "#director-timeline",
    );
    await expect(page.getByTestId("workflow-link-scheduling")).toHaveAttribute(
      "href",
      "#director-scheduling",
    );

    const attention = page.getByTestId("director-attention");
    await expect(attention).toContainText("Scoreboard offline for game #101");
    await expect(attention).toContainText("OPERATOR REQUIRED");
    await expect(attention).toContainText("Game #103 is late");

    const focus = page.getByTestId("director-focus");
    await expect(
      focus.getByText("#101 · Prior Lake Lakers vs Edina Hornets"),
    ).toBeVisible();

    await focus.getByLabel("Urgency").selectOption("LIVE");

    const focusGames = page.getByTestId("director-focus-games");
    await expect(focusGames).toContainText(
      "#101 · Prior Lake Lakers vs Edina Hornets",
    );
    await expect(focusGames).not.toContainText("Burnsville");

    const timeline = page.getByTestId("director-timeline");
    await expect(timeline).toContainText("Rink 1");
    await expect(timeline).toContainText("Rink 2");

    const scheduling = page.getByTestId("director-scheduling");
    await expect(scheduling).toContainText("Move a scheduled game");
    await expect(scheduling).toContainText(
      "authoritative server conflict engine",
    );
  });
});
