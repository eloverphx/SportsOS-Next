export type BroadcastOverlayDensity =
  | "COMPACT"
  | "STANDARD"
  | "LARGE";

export type BroadcastOverlayTheme = {
  id: string;
  name: string;
  homeAccent: string;
  awayAccent: string;
  panelBackground: string;
  textColor: string;
  mutedTextColor: string;
  showLogos: boolean;
  density: BroadcastOverlayDensity;
};

export const DEFAULT_BROADCAST_OVERLAY_THEME:
  BroadcastOverlayTheme = {
    id: "sportsos-dark",
    name: "SportsOS Dark",
    homeAccent: "#2563eb",
    awayAccent: "#dc2626",
    panelBackground: "rgba(2, 6, 23, 0.92)",
    textColor: "#ffffff",
    mutedTextColor: "#94a3b8",
    showLogos: true,
    density: "STANDARD",
  };

function normalizeHexColor(
  value: string | null | undefined,
  fallback: string,
): string {
  if (
    typeof value === "string" &&
    /^#[0-9a-fA-F]{6}$/.test(value)
  ) {
    return value;
  }

  return fallback;
}

export function buildBroadcastOverlayTheme(
  input?: Partial<BroadcastOverlayTheme>,
): BroadcastOverlayTheme {
  return {
    ...DEFAULT_BROADCAST_OVERLAY_THEME,
    ...input,
    homeAccent: normalizeHexColor(
      input?.homeAccent,
      DEFAULT_BROADCAST_OVERLAY_THEME.homeAccent,
    ),
    awayAccent: normalizeHexColor(
      input?.awayAccent,
      DEFAULT_BROADCAST_OVERLAY_THEME.awayAccent,
    ),
    panelBackground:
      input?.panelBackground?.trim() ||
      DEFAULT_BROADCAST_OVERLAY_THEME.panelBackground,
    textColor: normalizeHexColor(
      input?.textColor,
      DEFAULT_BROADCAST_OVERLAY_THEME.textColor,
    ),
    mutedTextColor: normalizeHexColor(
      input?.mutedTextColor,
      DEFAULT_BROADCAST_OVERLAY_THEME.mutedTextColor,
    ),
  };
}

export function overlayDensityClasses(
  density: BroadcastOverlayDensity,
): {
  score: string;
  team: string;
  clock: string;
  padding: string;
} {
  switch (density) {
    case "COMPACT":
      return {
        score: "text-3xl",
        team: "text-xs",
        clock: "text-3xl",
        padding: "px-4 py-3",
      };

    case "LARGE":
      return {
        score: "text-5xl",
        team: "text-base",
        clock: "text-5xl",
        padding: "px-6 py-5",
      };

    case "STANDARD":
    default:
      return {
        score: "text-4xl",
        team: "text-sm",
        clock: "text-4xl",
        padding: "px-5 py-4",
      };
  }
}
