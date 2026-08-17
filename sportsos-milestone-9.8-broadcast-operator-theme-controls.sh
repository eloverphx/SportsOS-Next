#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.8-broadcast-operator-theme-controls"
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

PANEL="apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx"
THEME_LIB="apps/dashboard/lib/broadcast-overlay-theme.ts"
THEME_SETTINGS_LIB="apps/dashboard/lib/broadcast-overlay-theme-settings.ts"
TEST="apps/dashboard/test/broadcast-overlay-theme-controls-9.8.test.ts"

for file in "$PANEL" "$THEME_LIB"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PANEL")" \
  "$BACKUP_DIR/$(dirname "$THEME_SETTINGS_LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

for file in "$PANEL" "$THEME_SETTINGS_LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$THEME_SETTINGS_LIB" <<'EOF'
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx";

let text = fs.readFileSync(file, "utf8");

if (!text.includes('from "../../lib/broadcast-overlay-theme-settings"')) {
  const importAnchor = `import {
  buildBroadcastSessionSummary,
  type BroadcastOverlayState,
  type BroadcastTransportState,
} from "../../lib/tournament-broadcast-session";`;

  if (!text.includes(importAnchor)) {
    throw new Error("Broadcast session import anchor not found.");
  }

  text = text.replace(
    importAnchor,
`${importAnchor}
import {
  BROADCAST_THEME_STORAGE_KEY,
  normalizeBroadcastOverlayThemeSettings,
  type BroadcastOverlayThemeSettings,
} from "../../lib/broadcast-overlay-theme-settings";`,
  );
}

if (!text.includes("const [themeSettings, setThemeSettings]")) {
  const stateAnchor = `  const [overlayState, setOverlayState] =
    useState<BroadcastOverlayState>("DISABLED");`;

  if (!text.includes(stateAnchor)) {
    throw new Error("Overlay state anchor not found.");
  }

  text = text.replace(
    stateAnchor,
`${stateAnchor}
  const [themeSettings, setThemeSettings] =
    useState<BroadcastOverlayThemeSettings>(() =>
      normalizeBroadcastOverlayThemeSettings(),
    );`,
  );
}

if (!text.includes("localStorage.setItem(BROADCAST_THEME_STORAGE_KEY")) {
  const summaryAnchor = `  const summary = useMemo(
    () =>
      buildBroadcastSessionSummary({`;

  const summaryIndex = text.indexOf(summaryAnchor);

  if (summaryIndex < 0) {
    throw new Error("Broadcast summary anchor not found.");
  }

  const insert = `  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(
        BROADCAST_THEME_STORAGE_KEY,
      );

      if (raw) {
        const parsed = JSON.parse(
          raw,
        ) as Partial<BroadcastOverlayThemeSettings>;

        setThemeSettings(
          normalizeBroadcastOverlayThemeSettings(parsed),
        );
      }
    } catch {
      // Ignore malformed or unavailable local storage.
    }
  }, []);

  useEffect(() => {
    try {
      window.localStorage.setItem(
        BROADCAST_THEME_STORAGE_KEY,
        JSON.stringify(themeSettings),
      );
    } catch {
      // Operator controls remain usable without persistence.
    }
  }, [themeSettings]);

`;

  text =
    text.slice(0, summaryIndex) +
    insert +
    text.slice(summaryIndex);
}

if (!text.includes('data-testid="broadcast-theme-controls"')) {
  const closingAnchor = `      <div className="grid gap-4 md:grid-cols-3">`;

  const idx = text.indexOf(closingAnchor);

  if (idx < 0) {
    throw new Error("Broadcast readiness metrics anchor not found.");
  }

  const controls = `      <section
        data-testid="broadcast-theme-controls"
        className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
      >
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Overlay theme
          </div>
          <h2 className="mt-1 text-lg font-bold text-slate-100">
            Branding controls
          </h2>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            These settings are saved in this browser and are intended for the
            local broadcast operator workflow.
          </p>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Home accent
            </span>
            <input
              type="color"
              value={themeSettings.homeAccent}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    homeAccent: event.target.value,
                  }),
                )
              }
              className="h-10 w-full rounded-lg border border-slate-800 bg-slate-950 p-1"
            />
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Away accent
            </span>
            <input
              type="color"
              value={themeSettings.awayAccent}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    awayAccent: event.target.value,
                  }),
                )
              }
              className="h-10 w-full rounded-lg border border-slate-800 bg-slate-950 p-1"
            />
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Overlay density
            </span>
            <select
              value={themeSettings.density}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    density: event.target
                      .value as BroadcastOverlayThemeSettings["density"],
                  }),
                )
              }
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            >
              <option value="COMPACT">COMPACT</option>
              <option value="STANDARD">STANDARD</option>
              <option value="LARGE">LARGE</option>
            </select>
          </label>

          <label className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={themeSettings.showLogos}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    showLogos: event.target.checked,
                  }),
                )
              }
            />
            Show team logos
          </label>
        </div>
      </section>

`;

  text =
    text.slice(0, idx) +
    controls +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
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
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.8 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - operator theme settings model"
echo "  - home / away color controls"
echo "  - logo toggle"
echo "  - compact / standard / large density selection"
echo "  - browser-local persistence"
echo "  - Milestone 9.8 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.9 - Overlay Theme Consumption / Sync"
