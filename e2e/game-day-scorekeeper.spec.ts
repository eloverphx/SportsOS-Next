import { expect, test, type Page, type Route } from "@playwright/test";

const scorekeeper = {
  id: 77,
  organizationId: 9,
  organizationName: "Prior Lake Hockey",
  firstName: "Game",
  lastName: "Operator",
  email: "scorekeeper@example.test",
  username: "scorekeeper",
  role: "scorekeeper",
  permissions: ["game.read", "game.score", "scoreboard.read", "stream.read"],
};

type GameSnapshot = {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonName: string;
  homeTeamId: number | null;
  awayTeamId: number | null;
  homeTeamName: string;
  awayTeamName: string;
  venue: string | null;
  status: "SCHEDULED" | "LIVE" | "FINAL";
  gamePhase: "PREGAME" | "REGULATION" | "FINAL";
  homeScore: number;
  awayScore: number;
  period: number;
  periodLabel: string;
  regulationPeriods: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  overtimeEnabled: boolean;
};

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  });
}

async function installSession(page: Page) {
  await page.addInitScript((user) => {
    window.localStorage.setItem("sportsos_token", "e2e-scorekeeper-token");
    window.localStorage.setItem("sportsos_user", JSON.stringify(user));
  }, scorekeeper);
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

      if (body.includes("40")) {
        namespaceConnected = true;
      }

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
          '0{"sid":"sportsos-e2e-socket","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}',
      });
    }

    return route.fulfill({
      status: 200,
      contentType: "text/plain; charset=UTF-8",
      body: namespaceConnected ? '40{"sid":"sportsos-e2e-namespace"}' : "6",
    });
  });
}

test.describe("game-day scorekeeper workflow", () => {
  test("pregame → goal → penalty → FINAL postgame", async ({ page }) => {
    const lifecycleCommands: string[] = [];
    const eventBodies: Array<Record<string, unknown>> = [];

    let game: GameSnapshot = {
      id: 42,
      organizationId: 9,
      organizationName: "Prior Lake Hockey",
      seasonName: "2026-27",
      homeTeamId: 101,
      awayTeamId: 202,
      homeTeamName: "Prior Lake Lakers",
      awayTeamName: "Edina Hornets",
      venue: "Rink 1",
      status: "SCHEDULED",
      gamePhase: "PREGAME",
      homeScore: 0,
      awayScore: 0,
      period: 1,
      periodLabel: "PERIOD 1",
      regulationPeriods: 3,
      clockRemainingMs: 1_200_000,
      clockRunning: false,
      clockStartedAt: null,
      intermissionRemainingMs: 0,
      intermissionRunning: false,
      intermissionStartedAt: null,
      overtimeEnabled: true,
    };

    let events: Array<Record<string, unknown>> = [];
    let penalties: Array<Record<string, unknown>> = [];

    const players = [
      {
        id: 1001,
        teamId: 101,
        firstName: "Alex",
        lastName: "Laker",
        preferredName: null,
        jerseyNumber: 18,
      },
      {
        id: 1002,
        teamId: 101,
        firstName: "Sam",
        lastName: "Assist",
        preferredName: null,
        jerseyNumber: 12,
      },
      {
        id: 1003,
        teamId: 101,
        firstName: "Taylor",
        lastName: "Second",
        preferredName: null,
        jerseyNumber: 7,
      },
      {
        id: 2001,
        teamId: 202,
        firstName: "Eddie",
        lastName: "Hornet",
        preferredName: null,
        jerseyNumber: 22,
      },
    ];

    await installSession(page);
    await installRealtimeFixture(page);

    await page.route("**/auth/me", (route) => json(route, { user: scorekeeper }));

    await page.route("**/scoreboard-devices", (route) =>
      json(route, {
        devices: [
          {
            id: 501,
            gameId: 42,
            name: "Rink 1 Scoreboard",
            status: "ONLINE",
            lastSeenAt: new Date().toISOString(),
          },
        ],
      }),
    );

    await page.route("**/games/42/event-players", (route) =>
      json(route, { players }),
    );

    await page.route("**/games/42/penalties", (route) =>
      json(route, { penalties }),
    );

    await page.route("**/games/42/events", async (route) => {
      const request = route.request();

      if (request.method() === "GET") {
        return json(route, { events });
      }

      if (request.method() !== "POST") {
        return json(route, { error: "Unsupported fixture method" }, 405);
      }

      const body = request.postDataJSON() as Record<string, unknown>;
      eventBodies.push(body);

      const normalizedPlayerId =
        body.playerId === null || body.playerId === undefined || body.playerId === ""
          ? null
          : Number(body.playerId);

      const event = {
        id: events.length + 1,
        type: body.type,
        side: body.side,
        period: game.period,
        clockRemainingMs: game.clockRemainingMs,
        playerName:
          normalizedPlayerId === 1001
            ? "Alex Laker"
            : normalizedPlayerId === 2001
              ? "Eddie Hornet"
              : null,
        playerJerseyNumber:
          normalizedPlayerId === 1001 ? 18 : normalizedPlayerId === 2001 ? 22 : null,
        penaltyCode: body.type === "PENALTY" ? body.penaltyCode : null,
        penaltyMinutes: body.type === "PENALTY" ? body.penaltyMinutes : null,
        voidedAt: null,
        createdAt: new Date().toISOString(),
      };

      events = [event, ...events];

      if (body.type === "GOAL") {
        if (body.side === "home") game.homeScore += 1;
        if (body.side === "away") game.awayScore += 1;
      }

      if (body.type === "PENALTY") {
        penalties = [
          {
            id: 701,
            gameEventId: event.id,
            gameId: 42,
            side: body.side,
            playerName: event.playerName,
            jerseyNumber: event.playerJerseyNumber,
            infraction: body.penaltyCode,
            originalDurationMs: Number(body.penaltyMinutes) * 60_000,
            remainingMs: Number(body.penaltyMinutes) * 60_000,
            running: false,
            startedAt: null,
            createdAt: new Date().toISOString(),
          },
        ];
      }

      return json(route, { event });
    });

    await page.route("**/games/42/lifecycle", async (route) => {
      const body = route.request().postDataJSON() as {
        command: string;
        commandId?: string;
      };

      expect(body.commandId).toBeTruthy();
      lifecycleCommands.push(body.command);

      if (body.command === "startGame") {
        game = {
          ...game,
          status: "LIVE",
          gamePhase: "REGULATION",
        };
      } else if (body.command === "finishGame") {
        game = {
          ...game,
          status: "FINAL",
          gamePhase: "FINAL",
          clockRunning: false,
          clockStartedAt: null,
          intermissionRunning: false,
          intermissionStartedAt: null,
        };
        penalties = [];
      }

      return json(route, {
        game,
        command: body.command,
        replayed: false,
      });
    });

    await page.route("**/games/42/scoring", async (route) => {
      const body = route.request().postDataJSON() as Record<string, unknown>;

      if (body.action === "pauseClock") {
        game = {
          ...game,
          clockRunning: false,
          clockStartedAt: null,
        };
      } else if (body.action === "startClock") {
        game = {
          ...game,
          status: "LIVE",
          gamePhase: "REGULATION",
          clockRunning: true,
          clockStartedAt: new Date().toISOString(),
        };
      }

      return json(route, { game });
    });

    await page.route("**/games/42", (route) => json(route, { game }));

    page.on("dialog", async (dialog) => {
      await dialog.accept();
    });

    await page.goto("/games/42/control");

    await expect(
      page.getByRole("heading", { name: "Game-day readiness" }),
    ).toBeVisible();

    await expect(page.getByText("SportsOS is ready for game operation.")).toBeVisible({
      timeout: 10_000,
    });

    await page.getByRole("button", { name: "START GAME" }).click();

    await expect.poll(() => lifecycleCommands).toContain("startGame");
    await expect(page.getByText("LIVE", { exact: false }).first()).toBeVisible();

    await page
      .getByText("Prior Lake Lakers", { exact: true })
      .locator("xpath=ancestor::*[self::section or self::article or self::div][.//button[normalize-space()='GOAL']][1]")
      .getByRole("button", { name: "GOAL", exact: true })
      .click();

    await expect(page.getByRole("dialog", { name: "Record goal" })).toBeVisible();

    await page.getByLabel("Scorer").selectOption("1001");
    await page.getByLabel("First assist").selectOption("1002");
    await page.getByLabel("Second assist").selectOption("1003");
    await page.getByRole("button", { name: "CONFIRM GOAL" }).click();

    await expect.poll(() => eventBodies.length).toBe(1);
    expect(eventBodies[0]).toMatchObject({
      type: "GOAL",
      side: "home",
      playerId: "1001",
      assist1PlayerId: "1002",
      assist2PlayerId: "1003",
    });

    await expect(page.getByText("Alex Laker", { exact: false }).first()).toBeVisible();
    await expect(page.getByText("1", { exact: true }).first()).toBeVisible();

    await page
      .getByText("Edina Hornets", { exact: true })
      .locator("xpath=ancestor::*[self::section or self::article or self::div][.//button[normalize-space()='2:00 PENALTY']][1]")
      .getByRole("button", { name: "2:00 PENALTY", exact: true })
      .click();

    await expect(page.getByRole("dialog", { name: "Record penalty" })).toBeVisible();

    const penaltyDialog = page.getByRole("dialog", { name: "Record penalty" });
    const penaltySelects = penaltyDialog.locator("select");

    await expect(penaltySelects).toHaveCount(3);
    await penaltySelects.nth(0).selectOption("2001");
    await penaltySelects.nth(1).selectOption("Hooking");
    await penaltySelects.nth(2).selectOption("2");
    await penaltyDialog.getByRole("button", { name: "CONFIRM PENALTY" }).click();

    await expect.poll(() => eventBodies.length).toBe(2);
    expect(eventBodies[1]).toMatchObject({
      type: "PENALTY",
      side: "away",
      playerId: "2001",
      penaltyCode: "Hooking",
      penaltyMinutes: 2,
    });

    await expect(page.getByRole("heading", { name: "Penalty clocks" })).toBeVisible();
    await expect(page.getByText("Hooking", { exact: true }).first()).toBeVisible();

    await page.getByRole("button", { name: "FINISH GAME" }).click();

    await expect.poll(() => lifecycleCommands).toEqual(["startGame", "finishGame"]);

    await expect(page.getByRole("heading", { name: "Postgame summary" })).toBeVisible();
    await expect(page.getByText("FINAL", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("Scoring recap")).toBeVisible();
    await expect(page.getByText("Penalty recap")).toBeVisible();
    await expect(page.getByRole("link", { name: "Engine diagnostics" })).toBeVisible();

    expect(game.status).toBe("FINAL");
    expect(game.gamePhase).toBe("FINAL");
    expect(game.homeScore).toBe(1);
    expect(game.awayScore).toBe(0);
  });
});
