#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.9-overlay-theme-consumption-sync"
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

for required in "$ROOT/.git" "$ROOT/package.json" "$ROOT/apps"; do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CLIENT="apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx"
PANEL="apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx"
SETTINGS_LIB="apps/dashboard/lib/broadcast-overlay-theme-settings.ts"
SYNC_LIB="apps/dashboard/lib/broadcast-overlay-theme-sync.ts"
TEST="apps/dashboard/test/broadcast-overlay-theme-sync-9.9.test.ts"

for file in "$CLIENT" "$PANEL" "$SETTINGS_LIB"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CLIENT")" \
  "$BACKUP_DIR/$(dirname "$PANEL")" \
  "$BACKUP_DIR/$(dirname "$SYNC_LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

for file in "$CLIENT" "$PANEL" "$SYNC_LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$SYNC_LIB" <<'EOF'
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes('from "../../lib/broadcast-overlay-theme-sync"')) {
  const anchor = `import {
  buildBroadcastOverlayTheme,
  overlayDensityClasses,
} from "../../lib/broadcast-overlay-theme";`;

  if (!text.includes(anchor)) {
    throw new Error("Overlay theme import anchor not found.");
  }

  text = text.replace(
    anchor,
`${anchor}
import {
  BROADCAST_THEME_CHANGED_EVENT,
  readBroadcastOverlayThemeSettings,
} from "../../lib/broadcast-overlay-theme-sync";`,
  );
}

if (!text.includes("const [themeSettings, setThemeSettings]")) {
  const anchor = `  const [realtimeConnected, setRealtimeConnected] =
    useState(false);`;

  if (!text.includes(anchor)) {
    throw new Error("Realtime state anchor not found.");
  }

  text = text.replace(
    anchor,
`${anchor}
  const [themeSettings, setThemeSettings] = useState(() =>
    buildBroadcastOverlayTheme(),
  );`,
  );
}

const oldThemeMemo = `  const theme = useMemo(
    () => buildBroadcastOverlayTheme(),
    [],
  );`;

if (text.includes(oldThemeMemo)) {
  text = text.replace(
    oldThemeMemo,
`  const theme = useMemo(
    () => buildBroadcastOverlayTheme(themeSettings),
    [themeSettings],
  );`,
  );
}

if (!text.includes("readBroadcastOverlayThemeSettings(window.localStorage)")) {
  const anchor = `  useEffect(() => {
    const timer = setInterval(() => {
      setClockNowMs(Date.now());
    }, 100);

    return () => {
      clearInterval(timer);
    };
  }, []);
`;

  if (!text.includes(anchor)) {
    throw new Error("Clock smoothing effect anchor not found.");
  }

  text = text.replace(
    anchor,
`${anchor}
  useEffect(() => {
    const refreshTheme = () => {
      setThemeSettings(
        buildBroadcastOverlayTheme(
          readBroadcastOverlayThemeSettings(
            window.localStorage,
          ),
        ),
      );
    };

    refreshTheme();

    const onStorage = (event: StorageEvent) => {
      if (
        !event.key ||
        event.key === "sportsos:broadcast-overlay-theme"
      ) {
        refreshTheme();
      }
    };

    window.addEventListener("storage", onStorage);
    window.addEventListener(
      BROADCAST_THEME_CHANGED_EVENT,
      refreshTheme,
    );

    return () => {
      window.removeEventListener("storage", onStorage);
      window.removeEventListener(
        BROADCAST_THEME_CHANGED_EVENT,
        refreshTheme,
      );
    };
  }, []);
`,
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("BROADCAST_THEME_CHANGED_EVENT")) {
  const anchor = `import {
  BROADCAST_THEME_STORAGE_KEY,
  normalizeBroadcastOverlayThemeSettings,
  type BroadcastOverlayThemeSettings,
} from "../../lib/broadcast-overlay-theme-settings";`;

  if (!text.includes(anchor)) {
    throw new Error("Theme settings import anchor not found.");
  }

  text = text.replace(
    anchor,
`${anchor}
import {
  BROADCAST_THEME_CHANGED_EVENT,
} from "../../lib/broadcast-overlay-theme-sync";`,
  );
}

const persistBlock = `      window.localStorage.setItem(
        BROADCAST_THEME_STORAGE_KEY,
        JSON.stringify(themeSettings),
      );`;

if (
  text.includes(persistBlock) &&
  !text.includes(
    "new Event(BROADCAST_THEME_CHANGED_EVENT)",
  )
) {
  text = text.replace(
    persistBlock,
`${persistBlock}
      window.dispatchEvent(
        new Event(BROADCAST_THEME_CHANGED_EVENT),
      );`,
  );
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
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
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.9 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - browser overlay consumes operator theme settings"
echo "  - cross-tab sync via storage event"
echo "  - same-window sync event"
echo "  - safe malformed-storage fallback"
echo "  - live theme refresh without page reload"
echo "  - Milestone 9.9 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.10 - Broadcast Operations Dashboard / Milestone 9 Closeout"
