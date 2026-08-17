import type {
  BroadcastOverlayDensity,
  BroadcastOverlayTheme,
} from "./broadcast-overlay-theme";
import {
  buildBroadcastOverlayTheme,
} from "./broadcast-overlay-theme";

export const BROADCAST_THEME_STORAGE_KEY =
  "sportsos:broadcast-overlay-theme";

export type BroadcastOverlayThemeSettings = {
  homeAccent: string;
  awayAccent: string;
  showLogos: boolean;
  density: BroadcastOverlayDensity;
};

export function normalizeBroadcastOverlayThemeSettings(
  input?: Partial<BroadcastOverlayThemeSettings>,
): BroadcastOverlayThemeSettings {
  const theme = buildBroadcastOverlayTheme({
    homeAccent: input?.homeAccent,
    awayAccent: input?.awayAccent,
    showLogos: input?.showLogos,
    density: input?.density,
  });

  return {
    homeAccent: theme.homeAccent,
    awayAccent: theme.awayAccent,
    showLogos: theme.showLogos,
    density: theme.density,
  };
}

export function themeSettingsToTheme(
  settings: BroadcastOverlayThemeSettings,
): BroadcastOverlayTheme {
  return buildBroadcastOverlayTheme(settings);
}
