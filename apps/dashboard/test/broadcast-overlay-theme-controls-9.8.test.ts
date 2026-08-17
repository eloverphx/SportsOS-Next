import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  BROADCAST_THEME_STORAGE_KEY,
  normalizeBroadcastOverlayThemeSettings,
} from "../lib/broadcast-overlay-theme-settings";

describe("Milestone 9.8 broadcast operator theme controls", () => {
  it("normalizes operator theme settings", () => {
    const settings =
      normalizeBroadcastOverlayThemeSettings({
        homeAccent: "#123456",
        awayAccent: "#abcdef",
        showLogos: false,
        density: "COMPACT",
      });

    expect(settings).toEqual({
      homeAccent: "#123456",
      awayAccent: "#abcdef",
      showLogos: false,
      density: "COMPACT",
    });
  });

  it("provides a stable browser persistence key", () => {
    expect(BROADCAST_THEME_STORAGE_KEY).toBe(
      "sportsos:broadcast-overlay-theme",
    );
  });

  it("renders operator branding controls", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="broadcast-theme-controls"',
    );
    expect(component).toContain('type="color"');
    expect(component).toContain("Show team logos");
    expect(component).toContain("Overlay density");
  });

  it("persists controls in localStorage", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "window.localStorage.getItem",
    );
    expect(component).toContain(
      "window.localStorage.setItem",
    );
    expect(component).toContain(
      "BROADCAST_THEME_STORAGE_KEY",
    );
  });
});
