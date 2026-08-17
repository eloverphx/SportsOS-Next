import {
  BROADCAST_THEME_STORAGE_KEY,
  normalizeBroadcastOverlayThemeSettings,
  type BroadcastOverlayThemeSettings,
} from "./broadcast-overlay-theme-settings";

export const BROADCAST_THEME_CHANGED_EVENT =
  "sportsos:broadcast-overlay-theme-changed";

export function readBroadcastOverlayThemeSettings(
  storage: Pick<Storage, "getItem">,
): BroadcastOverlayThemeSettings {
  try {
    const raw = storage.getItem(BROADCAST_THEME_STORAGE_KEY);

    if (!raw) {
      return normalizeBroadcastOverlayThemeSettings();
    }

    return normalizeBroadcastOverlayThemeSettings(
      JSON.parse(raw) as Partial<BroadcastOverlayThemeSettings>,
    );
  } catch {
    return normalizeBroadcastOverlayThemeSettings();
  }
}
