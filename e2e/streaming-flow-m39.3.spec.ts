import { expect, test, type Page, type Route } from "@playwright/test";

const organization = { id: 9, name: "Prior Lake Hockey" } as const;
const season = { id: 27, organizationId: 9, name: "2026-27" } as const;
const operator = {
  id: 77,
  organizationId: 9,
  organizationName: organization.name,
  firstName: "Broadcast",
  lastName: "Operator",
  email: "broadcast.operator@example.test",
  username: "broadcastoperator",
  role: "organization_admin",
  permissions: [
    "game.read",
    "game.manage",
    "game.score",
    "scoreboard.read",
    "stream.read",
    "stream.manage",
  ],
} as const;

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  });
}

async function installSession(page: Page) {
  await page.addInitScript((user) => {
    localStorage.setItem("sportsos_token", "m39-3-access-token");
    localStorage.setItem("sportsos_refresh_token", "m39-3-refresh-token");
    localStorage.setItem("sportsos_user", JSON.stringify(user));
  }, operator);
}

async function installRealtimeFixture(page: Page) {
  let connected = false;

  await page.route("**/socket.io/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());

    if (url.searchParams.get("transport") !== "polling") {
      return route.abort();
    }

    if (request.method() === "POST") {
      if ((request.postData() ?? "").includes("40")) connected = true;

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
        body: '0{"sid":"m39-3","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}',
      });
    }

    return route.fulfill({
      status: 200,
      contentType: "text/plain; charset=UTF-8",
      body: connected ? '40{"sid":"m39-3-ns"}' : "6",
    });
  });
}

test("M39.3 game to broadcast recording and archive playback", async ({ page }) => {
  let gameCreated = false;
  let createGamePayload: Record<string, unknown> | null = null;
  const lifecycleCommands: string[] = [];
  const coordinatorActions: string[] = [];
  let recordingReady = false;
  let coordinatorIntent = "IDLE";
  let goLiveStatus = "IDLE";
  let runtimeStatus = "IDLE";

  let game = {
    id: 42,
    organizationId: 9,
    organizationName: organization.name,
    seasonId: 27,
    seasonName: season.name,
    homeTeamId: null,
    awayTeamId: null,
    homeExternalName: "Prior Lake Lakers",
    awayExternalName: "Edina Hornets",
    homeTeamName: "Prior Lake Lakers",
    awayTeamName: "Edina Hornets",
    scheduledStart: "2026-09-12T19:00:00.000Z",
    timezone: "America/Chicago",
    venue: "Rink 1",
    status: "SCHEDULED",
    gamePhase: "PREGAME",
    homeScore: 0,
    awayScore: 0,
    period: 1,
    periodLabel: "PERIOD 1",
    regulationPeriods: 3,
    regulationPeriodLengthMs: 1_200_000,
    intermissionLengthMs: 900_000,
    overtimeEnabled: true,
    overtimeLengthMs: 300_000,
    notes: null,
    clockRemainingMs: 1_200_000,
    clockRunning: false,
    clockStartedAt: null,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
  };

  await installSession(page);
  await installRealtimeFixture(page);

  await page.route("**/auth/me", (route) => json(route, { user: operator }));
  await page.route("**/organizations", (route) => json(route, { organizations: [organization] }));
  await page.route("**/seasons", (route) => json(route, { seasons: [season] }));
  await page.route("**/games/team-options", (route) => json(route, { teams: [] }));

  await page.route("**/games", async (route) => {
    const request = route.request();

    // Do not intercept the Next.js /games document itself.
    // Only mock API fetch/XHR traffic to the same pathname.
    if (request.resourceType() === "document") {
      return route.fallback();
    }

    if (request.method() === "GET") {
      return json(route, { games: gameCreated ? [game] : [] });
    }

    if (request.method() !== "POST") {
      return json(route, { error: "Unsupported fixture method" }, 405);
    }

    createGamePayload = request.postDataJSON() as Record<string, unknown>;
    gameCreated = true;
    return json(route, { game }, 201);
  });

  await page.route("**/games/42/event-players", (route) => json(route, { players: [] }));
  await page.route("**/games/42/events", (route) => json(route, { events: [] }));
  await page.route("**/games/42/penalties", (route) => json(route, { penalties: [] }));
  await page.route("**/scoreboard-devices", (route) => json(route, { devices: [] }));

  await page.route("**/games/42/lifecycle", async (route) => {
    const body = route.request().postDataJSON() as { command: string; commandId?: string };

    expect(body.commandId).toBeTruthy();
    lifecycleCommands.push(body.command);

    if (body.command === "startGame") {
      game = { ...game, status: "LIVE", gamePhase: "REGULATION" };
    }

    return json(route, { game, command: body.command, replayed: false });
  });

  await page.route("**/games/42", (route) => json(route, { game }));

  await page.route("**/broadcast-coordinator/42/health", (route) =>
    json(route, { data: { health: { healthy: true, issues: [] } } }),
  );

  await page.route("**/broadcast-coordinator/42/retry", (route) =>
    json(route, {
      data: {
        retry: {
          state: "IDLE",
          attempts: 0,
          maxAttempts: 3,
          nextRetryAt: null,
          lastError: null,
        },
      },
    }),
  );

  await page.route("**/broadcast-coordinator/42/operator-timeline**", (route) =>
    json(route, { data: { events: [] } }),
  );
  await page.route("**/broadcast-coordinator/42/operator-notes", (route) =>
    json(route, { data: { notes: [] } }),
  );
  await page.route("**/broadcast-coordinator/42/resilience-status", (route) =>
    json(route, {
      data: {
        heartbeat: {
          state: "HEALTHY",
          stale: false,
          ageMs: 0,
          staleAfterMs: 15000,
          reason: "Recent heartbeat",
        },
        recovery: {
          action: "NONE",
          reason: "Runtime healthy",
          automatic: false,
          destructive: false,
        },
        persistedSnapshot: null,
      },
    }),
  );

  await page.route("**/broadcast-coordinator/42/prepare", async (route) => {
    coordinatorActions.push("prepare");
    coordinatorIntent = "PREPARE";
    goLiveStatus = "READY";
    return json(route, { data: { gameId: "42", intent: coordinatorIntent } });
  });

  await page.route("**/broadcast-coordinator/42/start", async (route) => {
    coordinatorActions.push("start");
    coordinatorIntent = "LIVE";
    goLiveStatus = "LIVE";
    runtimeStatus = "RUNNING";
    return json(route, { data: { gameId: "42", intent: coordinatorIntent } });
  });

  await page.route("**/broadcast-coordinator/42/stop", async (route) => {
    coordinatorActions.push("stop");
    coordinatorIntent = "STOPPED";
    goLiveStatus = "STOPPED";
    runtimeStatus = "STOPPED";
    recordingReady = true;
    return json(route, { data: { gameId: "42", intent: coordinatorIntent } });
  });

  await page.route("**/broadcast-coordinator/42", (route) =>
    json(route, {
      data: {
        coordinator: {
          intent: coordinatorIntent,
          correlationId: "m39-3-broadcast",
          updatedAt: new Date().toISOString(),
          lastError: null,
        },
        goLive: {
          status: goLiveStatus,
          degradationReason: null,
          emergencyStopReason: null,
        },
        runtime: {
          session: { status: runtimeStatus },
          telemetry: { health: "HEALTHY" },
        },
      },
    }),
  );

  await page.route("**/recordings?limit=100", (route) =>
    json(route, {
      recordings: recordingReady
        ? [
            {
              id: 501,
              organizationId: 9,
              gameId: 42,
              ownerUserId: 77,
              mediaAssetId: 9001,
              source: "LIVE",
              status: "READY",
              title: "Prior Lake Lakers vs Edina Hornets",
              startedAt: "2026-09-12T19:00:00.000Z",
              endedAt: "2026-09-12T20:30:00.000Z",
              durationMs: 5_400_000,
              publishedAt: "2026-09-12T20:31:00.000Z",
              createdAt: "2026-09-12T18:59:00.000Z",
              updatedAt: "2026-09-12T20:31:00.000Z",
              mediaUrl: null,
            },
          ]
        : [],
    }),
  );

  await page.route("**/media/assets/9001/playback-session", (route) =>
    json(route, {
      playbackUrl: "/media/playback/m39-3-recording",
      expiresAt: "2026-09-12T21:00:00.000Z",
    }),
  );

  await page.route("**/media/playback/m39-3-recording", (route) =>
    route.fulfill({ status: 200, contentType: "video/mp4", body: "" }),
  );

  page.on("dialog", async (dialog) => {
    await dialog.accept();
  });

  await page.goto("/games");
  await expect(page.getByRole("heading", { name: "Games" })).toBeVisible();
  await page.getByLabel("Season").selectOption(String(season.id));
  await page.getByLabel("External home name").fill("Prior Lake Lakers");
  await page.getByLabel("External away name").fill("Edina Hornets");
  await page.getByLabel("Scheduled start").fill("2026-09-12T19:00");
  await page.getByLabel("Venue").fill("Rink 1");
  await page.getByRole("button", { name: "Create game" }).click();

  await expect.poll(() => gameCreated).toBe(true);
  expect(createGamePayload).toMatchObject({
    organizationId: 9,
    seasonId: 27,
    homeTeamId: null,
    awayTeamId: null,
    homeExternalName: "Prior Lake Lakers",
    awayExternalName: "Edina Hornets",
    venue: "Rink 1",
  });

  await expect(
    page.getByRole("heading", { name: "Edina Hornets at Prior Lake Lakers" }),
  ).toBeVisible();

  await page.goto("/games/42/control");
  await expect(page.getByRole("heading", { name: "Game-day readiness" })).toBeVisible();
  await expect(page.getByText("SportsOS is ready for game operation.")).toBeVisible({
    timeout: 10000,
  });

  await page.getByRole("button", { name: "START GAME" }).click();
  await expect.poll(() => lifecycleCommands).toContain("startGame");

  await Promise.all([
    page.waitForURL(/\/broadcast\/operations\/42$/),
    page.getByRole("button", { name: "Prepare broadcast" }).click(),
  ]);

  await expect(page.getByRole("heading", { name: "Broadcast Focus — Game 42" })).toBeVisible();
  await expect.poll(() => coordinatorActions).toContain("prepare");

  const startButton = page.getByRole("button", { name: "Start", exact: true });
  await expect(startButton).toBeEnabled();
  await startButton.click();
  await expect.poll(() => coordinatorActions).toContain("start");
  await expect(page.getByText("LIVE", { exact: true }).first()).toBeVisible();
  await expect(page.getByText("RUNNING", { exact: true }).first()).toBeVisible();

  await page.getByRole("button", { name: "Stop", exact: true }).click();
  await expect.poll(() => coordinatorActions).toEqual(["prepare", "start", "stop"]);
  await expect(page.getByText("stop completed.")).toBeVisible();
  expect(recordingReady).toBe(true);

  await page.goto("/streaming");
  await expect(page.getByRole("heading", { name: "Recordings" })).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Prior Lake Lakers vs Edina Hornets" }),
  ).toBeVisible();
  await expect(page.getByText("READY", { exact: true }).first()).toBeVisible();

  await page.getByRole("button", { name: "Play recording" }).click();
  await expect(page.getByRole("heading", { name: "Recording #501" })).toBeVisible();
  await expect(page.locator("video")).toHaveAttribute("src", /\/media\/playback\/m39-3-recording$/);

  expect(lifecycleCommands).toEqual(["startGame"]);
  expect(coordinatorActions).toEqual(["prepare", "start", "stop"]);
});
