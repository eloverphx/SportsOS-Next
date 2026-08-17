import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.2 broadcast session API / operator UI", () => {
  it("provides a broadcast session API route", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/broadcast/session/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("buildBroadcastSessionSummary");
    expect(route).toContain("gameId is required");
  });

  it("renders the broadcast operator panel", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="broadcast-operator-panel"',
    );
    expect(component).toContain("Can go live");
    expect(component).toContain("Overlay eligible");
  });

  it("provides the tournament broadcast page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/broadcast/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain("Broadcast Operator");
    expect(page).toContain(
      "TournamentBroadcastOperatorPanel",
    );
  });
});
