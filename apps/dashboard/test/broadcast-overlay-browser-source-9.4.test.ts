import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.4 browser source overlay", () => {
  it("provides a per-game browser-source route", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/broadcast/overlay/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain("BroadcastOverlayClient");
    expect(page).toContain("gameId");
  });

  it("polls the authoritative overlay API", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "/api/tournament/broadcast/overlay/",
    );
    expect(component).toContain("setInterval");
    expect(component).toContain("1000");
  });

  it("renders scoreboard-safe overlay elements", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="broadcast-browser-overlay"',
    );
    expect(component).toContain(
      'data-testid="overlay-home-score"',
    );
    expect(component).toContain(
      'data-testid="overlay-away-score"',
    );
    expect(component).toContain(
      'data-testid="overlay-clock"',
    );
  });

  it("keeps the browser source transparent", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("bg-transparent");
  });
});
