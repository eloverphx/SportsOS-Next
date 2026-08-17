import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildBroadcastOperationsSummary,
} from "../lib/tournament-broadcast-operations";

describe("Milestone 9.10 broadcast operations dashboard", () => {
  it("reports ready when the stream can go live", () => {
    const summary = buildBroadcastOperationsSummary({
      sessionReady: true,
      canGoLive: true,
      gameLive: false,
      transportLive: false,
      overlayEligible: true,
      realtimeConnected: true,
    });

    expect(summary.stage).toBe("READY");
  });

  it("reports live when game and transport are both live", () => {
    const summary = buildBroadcastOperationsSummary({
      sessionReady: true,
      canGoLive: false,
      gameLive: true,
      transportLive: true,
      overlayEligible: true,
      realtimeConnected: true,
    });

    expect(summary.stage).toBe("LIVE");
  });

  it("reports degraded when realtime is unavailable during a live broadcast", () => {
    const summary = buildBroadcastOperationsSummary({
      sessionReady: true,
      canGoLive: false,
      gameLive: true,
      transportLive: true,
      overlayEligible: true,
      realtimeConnected: false,
    });

    expect(summary.stage).toBe("DEGRADED");
  });

  it("renders the broadcast operations dashboard", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperationsDashboard.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="broadcast-operations-dashboard"',
    );
    expect(component).toContain(
      'data-testid="broadcast-overlay-url"',
    );
    expect(component).toContain(
      "TournamentBroadcastOperatorPanel",
    );
  });

  it("provides the broadcast operations page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Broadcast Operations Dashboard",
    );
    expect(page).toContain(
      "TournamentBroadcastOperationsDashboard",
    );
  });
});
