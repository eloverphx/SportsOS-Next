#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.7-broadcast-overlay-themes-branding"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CLIENT="apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx"
THEME_LIB="apps/dashboard/lib/broadcast-overlay-theme.ts"
THEME_TEST="apps/dashboard/test/broadcast-overlay-theme-9.7.test.ts"

[[ -f "$CLIENT" ]] || {
  echo "ERROR: Milestone 9.6 browser overlay missing: $CLIENT" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CLIENT")" \
  "$BACKUP_DIR/$(dirname "$THEME_LIB")" \
  "$BACKUP_DIR/$(dirname "$THEME_TEST")"

for file in "$CLIENT" "$THEME_LIB" "$THEME_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$THEME_LIB" <<'EOF'
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx";

let text = fs.readFileSync(file, "utf8");

const clockImport = `import {
  deriveSmoothedRemainingMs,
  formatOverlayClock,
} from "../../lib/broadcast-overlay-clock";`;

if (!text.includes('from "../../lib/broadcast-overlay-theme"')) {
  if (!text.includes(clockImport)) {
    throw new Error("Clock import anchor not found.");
  }

  text = text.replace(
    clockImport,
`${clockImport}
import {
  buildBroadcastOverlayTheme,
  overlayDensityClasses,
} from "../../lib/broadcast-overlay-theme";`,
  );
}

if (!text.includes("const theme = useMemo(")) {
  const powerPlayAnchor = `  const powerPlayLabel = useMemo(() => {`;

  if (!text.includes(powerPlayAnchor)) {
    throw new Error("Power-play memo anchor not found.");
  }

  text = text.replace(
    powerPlayAnchor,
`  const theme = useMemo(
    () => buildBroadcastOverlayTheme(),
    [],
  );

  const density = useMemo(
    () => overlayDensityClasses(theme.density),
    [theme.density],
  );

${powerPlayAnchor}`,
  );
}

text = text.replace(
  'className="absolute inset-x-0 bottom-8 mx-auto flex w-[min(94vw,1200px)] items-stretch overflow-hidden rounded-2xl border border-white/15 bg-slate-950/90 text-white shadow-2xl backdrop-blur"',
  'className="absolute inset-x-0 bottom-8 mx-auto flex w-[min(94vw,1200px)] items-stretch overflow-hidden rounded-2xl border border-white/15 shadow-2xl backdrop-blur"',
);

if (!text.includes("backgroundColor: theme.panelBackground")) {
  text = text.replace(
`      <div className="absolute inset-x-0 bottom-8 mx-auto flex w-[min(94vw,1200px)] items-stretch overflow-hidden rounded-2xl border border-white/15 shadow-2xl backdrop-blur">`,
`      <div
        className="absolute inset-x-0 bottom-8 mx-auto flex w-[min(94vw,1200px)] items-stretch overflow-hidden rounded-2xl border border-white/15 shadow-2xl backdrop-blur"
        style={{
          backgroundColor: theme.panelBackground,
          color: theme.textColor,
        }}
      >`,
  );
}

text = text.replaceAll(
  'className="flex min-w-0 flex-1 items-center gap-4 px-5 py-4"',
  'className={`flex min-w-0 flex-1 items-center gap-4 ${density.padding}`}',
);

text = text.replace(
  'className="truncate text-sm font-semibold uppercase tracking-wide text-slate-400"',
  'className={`truncate ${density.team} font-semibold uppercase tracking-wide`}',
);

text = text.replace(
  'className="truncate text-sm font-semibold uppercase tracking-wide text-slate-400"',
  'className={`truncate ${density.team} font-semibold uppercase tracking-wide`}',
);

text = text.replaceAll(
  'className="text-4xl font-black leading-none"',
  'className={`${density.score} font-black leading-none`}',
);

text = text.replace(
  'className="font-mono text-4xl font-black tabular-nums"',
  'className={`font-mono ${density.clock} font-black tabular-nums`}',
);

if (!text.includes("borderLeftColor: theme.homeAccent")) {
  text = text.replace(
`        <div className={\`flex min-w-0 flex-1 items-center gap-4 \${density.padding}\`}>`,
`        <div
          className={\`flex min-w-0 flex-1 items-center gap-4 \${density.padding}\`}
          style={{
            borderLeft: "6px solid",
            borderLeftColor: theme.homeAccent,
          }}
        >`,
  );
}

const lastTeamDiv = `        <div className={\`flex min-w-0 flex-1 items-center gap-4 \${density.padding}\`}>`;
const lastIndex = text.lastIndexOf(lastTeamDiv);

if (
  lastIndex >= 0 &&
  !text.slice(lastIndex, lastIndex + 250).includes(
    "borderRightColor: theme.awayAccent",
  )
) {
  text =
    text.slice(0, lastIndex) +
    `        <div
          className={\`flex min-w-0 flex-1 items-center gap-4 \${density.padding}\`}
          style={{
            borderRight: "6px solid",
            borderRightColor: theme.awayAccent,
          }}
        >` +
    text.slice(lastIndex + lastTeamDiv.length);
}

text = text.replaceAll(
  'className="truncate text-sm font-semibold uppercase tracking-wide text-slate-400"',
  'className={`truncate ${density.team} font-semibold uppercase tracking-wide`}',
);

text = text.replaceAll(
  'className={`truncate ${density.team} font-semibold uppercase tracking-wide`}',
  'className={`truncate ${density.team} font-semibold uppercase tracking-wide`}\n              style={{ color: theme.mutedTextColor }}',
);

text = text.replace(
  "{snapshot.home.logoUrl ? (",
  "{theme.showLogos && snapshot.home.logoUrl ? (",
);

text = text.replace(
  "{snapshot.away.logoUrl ? (",
  "{theme.showLogos && snapshot.away.logoUrl ? (",
);

fs.writeFileSync(file, text);
NODE

cat > "$THEME_TEST" <<'EOF'
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
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.7 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - reusable overlay theme model"
echo "  - home / away accent colors"
echo "  - panel / text / muted colors"
echo "  - logo visibility control"
echo "  - compact / standard / large density presets"
echo "  - browser overlay theme wiring"
echo "  - Milestone 9.7 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.8 - Broadcast Operator Theme Controls"
