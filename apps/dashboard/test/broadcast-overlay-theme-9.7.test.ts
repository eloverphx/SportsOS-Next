import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildBroadcastOverlayTheme,
  DEFAULT_BROADCAST_OVERLAY_THEME,
  overlayDensityClasses,
} from "../lib/broadcast-overlay-theme";

describe("Milestone 9.7 broadcast overlay themes / branding", () => {
  it("provides a safe default theme", () => {
    expect(buildBroadcastOverlayTheme()).toEqual(
      DEFAULT_BROADCAST_OVERLAY_THEME,
    );
  });

  it("accepts valid custom team colors", () => {
    const theme = buildBroadcastOverlayTheme({
      homeAccent: "#112233",
      awayAccent: "#abcdef",
    });

    expect(theme.homeAccent).toBe("#112233");
    expect(theme.awayAccent).toBe("#abcdef");
  });

  it("rejects invalid hex colors and falls back safely", () => {
    const theme = buildBroadcastOverlayTheme({
      homeAccent: "blue",
      awayAccent: "#123",
    });

    expect(theme.homeAccent).toBe(
      DEFAULT_BROADCAST_OVERLAY_THEME.homeAccent,
    );
    expect(theme.awayAccent).toBe(
      DEFAULT_BROADCAST_OVERLAY_THEME.awayAccent,
    );
  });

  it("maps overlay density to presentation classes", () => {
    expect(
      overlayDensityClasses("COMPACT").score,
    ).toBe("text-3xl");

    expect(
      overlayDensityClasses("STANDARD").score,
    ).toBe("text-4xl");

    expect(
      overlayDensityClasses("LARGE").score,
    ).toBe("text-5xl");
  });

  it("wires theme colors and logo visibility into the browser overlay", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "buildBroadcastOverlayTheme",
    );
    expect(component).toContain(
      "theme.homeAccent",
    );
    expect(component).toContain(
      "theme.awayAccent",
    );
    expect(component).toContain(
      "theme.showLogos",
    );
  });
});
