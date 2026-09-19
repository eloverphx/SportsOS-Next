import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

function source(relativePath: string): string {
  return fs.readFileSync(path.join(process.cwd(), relativePath), "utf8");
}

describe("M40.4 game-day UX contracts", () => {
  it("keeps Games as the main launch point for scorekeeper and broadcast operations", () => {
    const games = source("apps/dashboard/app/games/page.tsx");

    expect(games).toContain("href={`/games/${game.id}/control`}");
    expect(games).toContain("href={`/broadcast/operations/${game.id}`}");
    expect(games).toContain("Scorekeeper");
    expect(games).toContain("Broadcast");
  });

  it("keeps the Scoreboards device page inside normal SportsOS navigation", () => {
    const scoreboards = source("apps/dashboard/app/scoreboards/page.tsx");

    expect(scoreboards).toContain("import { AuthGate }");
    expect(scoreboards).toContain("import { AppShell }");
    expect(scoreboards).toContain("<AuthGate>");
    expect(scoreboards).toContain("<AppShell>");
    expect(scoreboards).toContain("<ScoreboardDeviceOperations");
  });

  it("gives the focused scorekeeper an explicit route back to Games", () => {
    const scorekeeper = source("apps/dashboard/app/games/[id]/control/page.tsx");

    expect(scorekeeper).toContain('href="/games"');
    expect(scorekeeper).toContain("← Back to Games");
  });

  it("keeps normal broadcast start outside Advanced controls", () => {
    const broadcast = source("apps/dashboard/app/broadcast/operations/[gameId]/page.tsx");

    const advancedIndex = broadcast.indexOf("Advanced controls");
    const advancedCloseIndex = broadcast.indexOf("</details>", advancedIndex);
    const primaryStartIndex = broadcast.indexOf("onClick={() => void startBroadcast()}");

    expect(advancedIndex).toBeGreaterThan(-1);
    expect(advancedCloseIndex).toBeGreaterThan(advancedIndex);
    expect(primaryStartIndex).toBeGreaterThan(advancedCloseIndex);

    expect(broadcast).toContain("Start Broadcast");
    expect(broadcast).toContain("Stop Broadcast & Finalize Recording");
  });

  it("automates prepare, health hold, live confirmation, and recording start", () => {
    const broadcast = source("apps/dashboard/app/broadcast/operations/[gameId]/page.tsx");

    expect(broadcast).toContain("`/broadcast-coordinator/${encodeURIComponent(gameId)}/prepare`");
    expect(broadcast).toContain("`/broadcast-coordinator/${encodeURIComponent(gameId)}/start`");
    expect(broadcast).toContain("`/go-live-sessions/${encodeURIComponent(gameId)}/health-hold`");
    expect(broadcast).toContain("`/go-live-sessions/${encodeURIComponent(gameId)}/confirm-live`");
    expect(broadcast).toContain("readyToConfirm");
    expect(broadcast).toContain("recordingCapture");
    expect(broadcast).not.toContain("Start Recording");
  });

  it("shows Stop only for an active live or recording state", () => {
    const broadcast = source("apps/dashboard/app/broadcast/operations/[gameId]/page.tsx");

    expect(broadcast).toContain('recording?.status === "RECORDING"');
    expect(broadcast).toContain('snapshot.goLive.status === "LIVE"');
    expect(broadcast).toContain('snapshot.runtime.session.status === "LIVE"');
    expect(broadcast).toContain('onClick={() => void runCoordinatorAction("stop")}');
  });

  it("keeps the operations overview linked to the focused per-game workflow", () => {
    const operations = source("apps/dashboard/app/broadcast/operations/page.tsx");

    expect(operations).toContain("/broadcast/operations/");
    expect(operations).toContain("Open Game");
    expect(operations).toContain("Advanced controls");
  });
});

describe("M40.4 authentication resilience contracts", () => {
  it("does not treat every AuthGate verification error as a logout", () => {
    const authGate = source("apps/dashboard/components/AuthGate.tsx");

    expect(authGate).toContain("ApiError");
    expect(authGate).toContain("confirmedAuthenticationFailure");
    expect(authGate).toContain("temporarilyUnavailable");
    expect(authGate).toContain("Retry connection");
    expect(authGate).toContain("Your session is still saved");
  });

  it("distinguishes refresh authentication failures from service outages", () => {
    const sessionRefresh = source("apps/dashboard/lib/session-refresh.ts");

    expect(sessionRefresh).toContain("SessionRefreshError");
    expect(sessionRefresh).toContain("confirmedAuthenticationFailure");
    expect(sessionRefresh).toContain("response.status === 401");
    expect(sessionRefresh).toContain("response.status === 403");
    expect(sessionRefresh).toContain("Preserve local credentials");
  });

  it("preserves refresh failure status through the authenticated API layer", () => {
    const authenticatedApi = source("apps/dashboard/lib/authenticated-api.ts");

    expect(authenticatedApi).toContain("SessionRefreshError");
    expect(authenticatedApi).toContain("new ApiError(error.message, error.status)");
  });
});
