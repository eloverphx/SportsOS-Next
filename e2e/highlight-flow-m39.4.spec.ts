import { expect, test, type Page, type Route } from "@playwright/test";

const operator = {
  id: 77,
  organizationId: 9,
  organizationName: "Prior Lake Hockey",
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
    localStorage.setItem("sportsos_token", "m39-4-access-token");
    localStorage.setItem("sportsos_refresh_token", "m39-4-refresh-token");
    localStorage.setItem("sportsos_user", JSON.stringify(user));
  }, operator);
}

test("M39.4 authoritative scorekeeper event to highlight playback", async ({ page }) => {
  const recordingId = 501;
  const gameEventId = 801;
  const clipJobId = 701;
  const clipMediaAssetId = 9201;

  let clipQueued = false;
  let clipReady = false;
  let queueRequestCount = 0;
  let queueRequestBody: string | null = "not-observed";
  let playbackSessionRequests = 0;

  const recording = {
    id: recordingId,
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
    mediaUrl: "/media/9001",
  };

  const anchor = {
    id: 601,
    recordingId,
    gameEventId,
    recordingOffsetMs: 1_830_000,
    anchorSource: "SCOREKEEPER",
    eventType: "GOAL",
    side: "home",
    period: 2,
    clockRemainingMs: 570_000,
    playerId: 1001,
    playerName: "Alex Laker",
    playerJerseyNumber: 18,
    assist1PlayerId: 1002,
    assist2PlayerId: 1003,
    voidedAt: null,
    eventCreatedAt: "2026-09-12T19:30:30.000Z",
    eligibleForHighlights: true,
    suggestedClipWindow: {
      startMs: 1_815_000,
      endMs: 1_840_000,
      durationMs: 25_000,
    },
  };

  const pendingJob = {
    id: clipJobId,
    organizationId: 9,
    recordingId,
    gameEventId,
    requestedByUserId: 77,
    selectionSource: "SCOREKEEPER_EVENT",
    startMs: 1_815_000,
    endMs: 1_840_000,
    durationMs: 25_000,
    status: "PENDING",
    outputMediaAssetId: null,
    errorMessage: null,
    attemptCount: 0,
    claimedAt: null,
    createdAt: "2026-09-12T20:32:00.000Z",
    updatedAt: "2026-09-12T20:32:00.000Z",
  };

  const readyJob = {
    ...pendingJob,
    status: "READY",
    outputMediaAssetId: clipMediaAssetId,
    attemptCount: 1,
    claimedAt: "2026-09-12T20:32:01.000Z",
    updatedAt: "2026-09-12T20:32:04.000Z",
  };

  await installSession(page);

  await page.route("**/auth/me", (route) => json(route, { user: operator }));

  await page.route("**/recordings?limit=100", (route) =>
    json(route, {
      recordings: [recording],
    }),
  );

  await page.route(`**/recordings/${recordingId}/event-anchors`, (route) =>
    json(route, {
      recordingId,
      anchors: [anchor],
    }),
  );

  await page.route(`**/recordings/${recordingId}/clip-jobs`, (route) =>
    json(route, {
      recordingId,
      clipJobs: clipQueued ? [clipReady ? readyJob : pendingJob] : [],
    }),
  );

  await page.route(
    `**/recordings/${recordingId}/event-anchors/${gameEventId}/clip-jobs`,
    async (route) => {
      expect(route.request().method()).toBe("POST");

      queueRequestCount += 1;
      queueRequestBody = route.request().postData();

      clipQueued = true;

      return json(
        route,
        {
          clipJob: pendingJob,
        },
        201,
      );
    },
  );

  await page.route(`**/media/assets/${clipMediaAssetId}/playback-session`, (route) => {
    playbackSessionRequests += 1;

    return json(route, {
      playbackUrl: "/media/playback/m39-4-highlight",
      expiresAt: "2026-09-12T21:00:00.000Z",
    });
  });

  await page.route("**/media/playback/m39-4-highlight", (route) =>
    route.fulfill({
      status: 200,
      contentType: "video/mp4",
      body: "",
    }),
  );

  await page.goto("/streaming");

  await expect(page.getByRole("heading", { name: "Recordings" })).toBeVisible();

  await expect(
    page.getByRole("heading", {
      name: "Prior Lake Lakers vs Edina Hornets",
    }),
  ).toBeVisible();

  await page.getByRole("button", { name: "Highlights" }).click();

  await expect(page.getByText("Authoritative event clips")).toBeVisible();

  await expect(
    page.getByText("GOAL · HOME · P2 9:30 · Alex Laker", {
      exact: true,
    }),
  ).toBeVisible();

  await expect(page.getByText(/Event #801 · SCOREKEEPER · offset/)).toBeVisible();

  await page.getByRole("button", { name: "Generate clip" }).click();

  await expect.poll(() => queueRequestCount).toBe(1);

  // The client selects the authoritative event only.
  // It must not submit arbitrary start/end timing.
  expect(queueRequestBody).toBeNull();

  await expect(page.getByText(`Clip job #${clipJobId} · PENDING`)).toBeVisible();

  clipReady = true;

  await page.getByRole("button", { name: "Refresh clips" }).click();

  await expect(page.getByText(`Clip job #${clipJobId} · READY`)).toBeVisible();

  await expect(page.getByText(/SCOREKEEPER_EVENT/)).toBeVisible();

  await page.getByRole("button", { name: "Play clip" }).click();

  await expect.poll(() => playbackSessionRequests).toBe(1);

  const player = page.locator("video");

  await expect(player).toBeVisible();
  await expect(player).toHaveAttribute("src", /\/media\/playback\/m39-4-highlight$/);

  expect(anchor.anchorSource).toBe("SCOREKEEPER");
  expect(anchor.gameEventId).toBe(gameEventId);
  expect(readyJob.selectionSource).toBe("SCOREKEEPER_EVENT");
  expect(readyJob.outputMediaAssetId).toBe(clipMediaAssetId);
});
