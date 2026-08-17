import { describe, expect, it } from "vitest";
import {
  buildBroadcastSessionSummary,
} from "../lib/tournament-broadcast-session";

describe("Milestone 9.1 broadcast session state", () => {
  it("reports ready when all broadcast prerequisites are satisfied", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-1",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "READY",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("READY");
    expect(summary.ready).toBe(true);
    expect(summary.canGoLive).toBe(true);
    expect(summary.blockers).toEqual([]);
  });

  it("blocks when no operator is assigned", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-2",
      operatorAssigned: false,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "READY",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("NOT_READY");
    expect(summary.blockers).toContain(
      "Broadcast operator is not assigned.",
    );
  });

  it("blocks when the stream destination is not configured", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-3",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "READY",
      streamKeyConfigured: false,
    });

    expect(summary.ready).toBe(false);
    expect(summary.blockers).toContain(
      "Stream destination is not configured.",
    );
  });

  it("reports live when game and transport are both live", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-4",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: true,
      transportState: "LIVE",
      overlayState: "ACTIVE",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("LIVE");
    expect(summary.ready).toBe(true);
    expect(summary.canGoLive).toBe(false);
  });

  it("reports degraded when the game is live but transport is not", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-5",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: true,
      transportState: "READY",
      overlayState: "ACTIVE",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("DEGRADED");
    expect(summary.warnings).toContain(
      "Game is live but broadcast transport is not live.",
    );
  });

  it("warns when transport is live before the game", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-6",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "LIVE",
      overlayState: "READY",
      streamKeyConfigured: true,
    });

    expect(summary.status).toBe("DEGRADED");
    expect(summary.warnings).toContain(
      "Broadcast transport is live before the game is live.",
    );
  });

  it("keeps overlay eligibility separate from transport readiness", () => {
    const summary = buildBroadcastSessionSummary({
      gameId: "game-7",
      operatorAssigned: true,
      gameAuthorized: true,
      gameLive: false,
      transportState: "READY",
      overlayState: "DISABLED",
      streamKeyConfigured: true,
    });

    expect(summary.overlayEligible).toBe(false);
    expect(summary.warnings).toContain(
      "Broadcast overlay is disabled.",
    );
  });
});
