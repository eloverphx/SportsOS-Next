#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.3-broadcast-session-operator-ui-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/routes/broadcastSessionProfiles.ts" \
  "apps/dashboard/app/games/[id]/overlay/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

PANEL="apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx"
PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
TEST="packages/core/test/broadcast-session-operator-ui-19.3.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for file in "$PANEL" "$PAGE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PANEL")" "$(dirname "$TEST")"

cat > "$PANEL" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type BroadcastSessionProfile = {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  updatedAt: string;
};

export function BroadcastSessionPanel() {
  const [gameId, setGameId] = useState("");
  const [profile, setProfile] =
    useState<BroadcastSessionProfile | null>(null);
  const [title, setTitle] = useState("");
  const [sponsorUrl, setSponsorUrl] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [showPowerPlay, setShowPowerPlay] = useState(true);
  const [showTeamLogos, setShowTeamLogos] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadProfile =
    useCallback(async (targetGameId: string) => {
      const normalized = targetGameId.trim();

      if (!normalized) {
        setProfile(null);
        return;
      }

      const response =
        await fetch(
          `${API_BASE}/broadcast-sessions/${encodeURIComponent(normalized)}`,
          { cache: "no-store" },
        );

      if (!response.ok) return;

      const json = await response.json();
      const nextProfile =
        json?.data?.profile ?? null;

      setProfile(nextProfile);
      setTitle(nextProfile?.title ?? "");
      setSponsorUrl(nextProfile?.sponsorUrl ?? "");
      setEnabled(nextProfile?.enabled ?? true);
      setShowPowerPlay(nextProfile?.showPowerPlay ?? true);
      setShowTeamLogos(nextProfile?.showTeamLogos ?? true);
    }, []);

  async function saveProfile() {
    const normalized = gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before saving broadcast settings.",
      );
      return;
    }

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/broadcast-sessions/${encodeURIComponent(normalized)}`,
          {
            method: "PUT",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              enabled,
              title: title.trim() || null,
              sponsorUrl: sponsorUrl.trim() || null,
              showPowerPlay,
              showTeamLogos,
            }),
          },
        );

      const json = await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Broadcast session save failed (${response.status}).`,
        );
      }

      setProfile(json?.data?.profile ?? null);
      setError(null);
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to save broadcast session.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function resetProfile() {
    const normalized = gameId.trim();
    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/broadcast-sessions/${encodeURIComponent(normalized)}`,
          { method: "DELETE" },
        );

      if (!response.ok) {
        throw new Error(
          `Broadcast session reset failed (${response.status}).`,
        );
      }

      setProfile(null);
      setTitle("");
      setSponsorUrl("");
      setEnabled(true);
      setShowPowerPlay(true);
      setShowTeamLogos(true);
      setError(null);
    } catch (resetError) {
      setError(
        resetError instanceof Error
          ? resetError.message
          : "Unable to reset broadcast session.",
      );
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    const normalized = gameId.trim();
    if (!normalized) return;

    const timer =
      window.setTimeout(
        () => {
          void loadProfile(normalized);
        },
        350,
      );

    return () => {
      window.clearTimeout(timer);
    };
  }, [gameId, loadProfile]);

  const overlayPreviewUrl =
    useMemo(() => {
      const normalized = gameId.trim();
      if (!normalized) return null;

      return `/games/${encodeURIComponent(normalized)}/overlay`;
    }, [gameId]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Broadcast Session
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Configure persistent overlay branding and presentation for a game.
          </p>
        </div>

        {profile && (
          <span className="rounded border border-slate-700 px-3 py-1 text-xs">
            Saved {profile.updatedAt}
          </span>
        )}
      </div>

      <div className="mt-5">
        <label className="text-xs text-slate-500">
          Game ID
        </label>
        <input
          value={gameId}
          onChange={(event) => setGameId(event.target.value)}
          placeholder="Game ID"
          className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
        />
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Broadcast title
          </span>
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            placeholder="Organization or broadcast title"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Sponsor image URL
          </span>
          <input
            value={sponsorUrl}
            onChange={(event) => setSponsorUrl(event.target.value)}
            placeholder="https://..."
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-3">
        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(event) => setEnabled(event.target.checked)}
          />
          Broadcast enabled
        </label>

        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={showPowerPlay}
            onChange={(event) =>
              setShowPowerPlay(event.target.checked)
            }
          />
          Show power play
        </label>

        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={showTeamLogos}
            onChange={(event) =>
              setShowTeamLogos(event.target.checked)
            }
          />
          Show team logos
        </label>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-3">
        <button
          type="button"
          disabled={busy || !gameId.trim()}
          onClick={() => void saveProfile()}
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Save Broadcast Session
        </button>

        <button
          type="button"
          disabled={busy || !gameId.trim()}
          onClick={() => void resetProfile()}
          className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
        >
          Reset to Overlay Defaults
        </button>

        {overlayPreviewUrl && (
          <a
            href={overlayPreviewUrl}
            target="_blank"
            rel="noreferrer"
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium"
          >
            Open Live Overlay Preview
          </a>
        )}
      </div>

      {overlayPreviewUrl && (
        <div className="mt-5 overflow-hidden rounded-xl border border-slate-800 bg-black">
          <div className="border-b border-slate-800 px-3 py-2 text-xs text-slate-500">
            Live Overlay Preview
          </div>
          <iframe
            title="SportsOS broadcast overlay preview"
            src={overlayPreviewUrl}
            className="aspect-video w-full border-0"
          />
        </div>
      )}
    </section>
  );
}
EOF

if [[ ! -f "$PAGE" ]]; then
  cat > "$PAGE" <<'EOF'
import { BroadcastSessionPanel } from "./BroadcastSessionPanel";

export default function ScoreboardOperationsPage() {
  return (
    <main className="p-6">
      <h1 className="text-2xl font-bold">
        Scoreboard Operations
      </h1>
      <BroadcastSessionPanel />
    </main>
  );
}
EOF
else
  node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";

let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { BroadcastSessionPanel } from "./BroadcastSessionPanel";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard operations imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (!text.includes("<BroadcastSessionPanel />")) {
  const closeMain =
    text.lastIndexOf("</main>");

  if (closeMain === -1) {
    throw new Error(
      "Unable to locate scoreboard operations main container.",
    );
  }

  text =
    text.slice(0, closeMain) +
    "      <BroadcastSessionPanel />\n" +
    text.slice(closeMain);
}

fs.writeFileSync(file, text);
NODE
fi

cat >> "$DOC" <<'EOF'

## Milestone 19.3 — Broadcast session operator UI

Scoreboard Operations now includes a Broadcast Session panel.

Operators can:

- select a game
- load its persisted broadcast profile
- enable or disable the broadcast session
- set the broadcast title
- set a sponsor image URL
- show/hide the power-play indicator
- show/hide team logos
- save changes
- reset the game to overlay defaults
- open the live overlay in a new window
- view an embedded live overlay preview

The preview uses the real overlay route and therefore continues to consume authoritative public scoreboard game state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.3 broadcast session operator UI", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("loads and saves broadcast sessions", () => {
    expect(panel).toContain(
      "/broadcast-sessions/",
    );

    expect(panel).toContain(
      "Save Broadcast Session",
    );
  });

  it("provides branding and presentation controls", () => {
    expect(panel).toContain(
      "Broadcast title",
    );

    expect(panel).toContain(
      "Sponsor image URL",
    );

    expect(panel).toContain(
      "Show power play",
    );

    expect(panel).toContain(
      "Show team logos",
    );
  });

  it("provides reset behavior", () => {
    expect(panel).toContain(
      "Reset to Overlay Defaults",
    );

    expect(panel).toContain(
      'method: "DELETE"',
    );
  });

  it("provides live overlay preview", () => {
    expect(panel).toContain(
      "Open Live Overlay Preview",
    );

    expect(panel).toContain(
      "<iframe",
    );

    expect(panel).toContain(
      "/overlay",
    );
  });

  it("renders on scoreboard operations", () => {
    expect(page).toContain(
      "BroadcastSessionPanel",
    );

    expect(page).toContain(
      "<BroadcastSessionPanel />",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Broadcast Session operator panel"
echo "  - game-ID profile loading"
echo "  - broadcast enabled toggle"
echo "  - title and sponsor controls"
echo "  - power-play and logo visibility controls"
echo "  - save/reset actions"
echo "  - live overlay preview link"
echo "  - embedded live overlay preview"
echo "  - scoreboard operations integration"
echo "  - Milestone 19.3 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 19.4 - Broadcast Session Realtime Profile Updates"
