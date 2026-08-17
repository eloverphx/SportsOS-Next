import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  BROADCAST_THEME_CHANGED_EVENT,
  readBroadcastOverlayThemeSettings,
} from "../lib/broadcast-overlay-theme-sync";

describe("Milestone 9.9 overlay theme consumption / sync", () => {
  it("reads persisted theme settings safely", () => {
    const settings = readBroadcastOverlayThemeSettings({
      getItem: () =>
        JSON.stringify({
          homeAccent: "#112233",
          awayAccent: "#445566",
          showLogos: false,
          density: "LARGE",
        }),
    });

    expect(settings).toEqual({
      homeAccent: "#112233",
      awayAccent: "#445566",
      showLogos: false,
      density: "LARGE",
    });
  });

  it("falls back safely when persisted theme JSON is malformed", () => {
    const settings = readBroadcastOverlayThemeSettings({
      getItem: () => "{bad json",
    });

    expect(settings.density).toBe("STANDARD");
    expect(settings.showLogos).toBe(true);
  });

  it("provides a stable same-window synchronization event", () => {
    expect(BROADCAST_THEME_CHANGED_EVENT).toBe(
      "sportsos:broadcast-overlay-theme-changed",
    );
  });

  it("makes the browser overlay consume local theme settings", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "readBroadcastOverlayThemeSettings",
    );
    expect(component).toContain(
      'window.addEventListener("storage"',
    );
    expect(component).toContain(
      "BROADCAST_THEME_CHANGED_EVENT",
    );
  });

  it("dispatches theme changes from the operator panel", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "window.dispatchEvent",
    );
    expect(component).toContain(
      "BROADCAST_THEME_CHANGED_EVENT",
    );
  });
});
