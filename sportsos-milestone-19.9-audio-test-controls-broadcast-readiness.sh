#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.9-audio-test-readiness-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx"
TEST="packages/core/test/broadcast-audio-readiness-19.9.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for required in \
  ".git" \
  "$PANEL" \
  "apps/api/src/services/broadcastSessionProfile.ts" \
  "apps/dashboard/app/games/[id]/overlay/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("function testAudioUrl")) {
  const marker =
    "export function BroadcastSessionPanel()";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate BroadcastSessionPanel component.",
    );
  }

  const helper =
`function testAudioUrl(
  url: string,
): void {
  const normalized =
    url.trim();

  if (!normalized) {
    return;
  }

  const audio =
    new Audio(
      normalized,
    );

  audio.preload =
    "auto";

  void audio.play().catch(
    () => {
      // Browser autoplay or invalid media must not break operator controls.
    },
  );
}

`;

  text =
    text.slice(0, idx) +
    helper +
    text.slice(idx);
}

if (!text.includes("const audioReadiness")) {
  const marker =
    `  const overlayPreviewUrl =
    useMemo(() => {`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate overlay preview memo.",
    );
  }

  const readiness =
`  const audioReadiness =
    useMemo(() => {
      const configured = [
        goalSoundUrl,
        penaltySoundUrl,
        hornSoundUrl,
        intermissionSoundUrl,
      ].filter(
        (url) =>
          url.trim().length > 0,
      ).length;

      if (!soundEnabled) {
        return {
          ready: true,
          label:
            "Audio disabled",
          detail:
            "Broadcast audio is intentionally muted.",
        };
      }

      if (configured === 0) {
        return {
          ready: false,
          label:
            "Audio not ready",
          detail:
            "Audio is enabled but no sound URLs are configured.",
        };
      }

      return {
        ready: true,
        label:
          "Audio ready",
        detail:
          \`\${configured} sound source\${configured === 1 ? "" : "s"} configured.\`,
      };
    }, [
      soundEnabled,
      goalSoundUrl,
      penaltySoundUrl,
      hornSoundUrl,
      intermissionSoundUrl,
    ]);

`;

  text =
    text.slice(0, idx) +
    readiness +
    text.slice(idx);
}

if (!text.includes("Test Goal Audio")) {
  const marker =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Broadcast Audio`;

  const start =
    text.indexOf(marker);

  if (start === -1) {
    throw new Error(
      "Unable to locate Broadcast Audio panel.",
    );
  }

  const nextSection =
    text.indexOf(
      '\n      <div className="mt-4 grid gap-3 md:grid-cols-3">',
      start,
    );

  if (nextSection === -1) {
    throw new Error(
      "Unable to locate insertion point after Broadcast Audio panel.",
    );
  }

  const block =
`
      <div className="mt-4 rounded-lg border border-slate-800 p-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="text-sm font-semibold">
              Audio Readiness
            </div>
            <div className="mt-1 text-xs text-slate-500">
              {audioReadiness.detail}
            </div>
          </div>

          <span
            className={
              \`rounded border px-3 py-1 text-xs font-medium \${
                audioReadiness.ready
                  ? "border-slate-700"
                  : "border-red-900/60 text-red-300"
              }\`
            }
          >
            {audioReadiness.label}
          </span>
        </div>

        <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          <button
            type="button"
            disabled={!goalSoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                goalSoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Goal Audio
          </button>

          <button
            type="button"
            disabled={!penaltySoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                penaltySoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Penalty Audio
          </button>

          <button
            type="button"
            disabled={!hornSoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                hornSoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Horn Audio
          </button>

          <button
            type="button"
            disabled={!intermissionSoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                intermissionSoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Intermission Audio
          </button>
        </div>
      </div>

`;

  text =
    text.slice(0, nextSection) +
    block +
    text.slice(nextSection);
}

for (const required of [
  "function testAudioUrl",
  "const audioReadiness",
  "Audio Readiness",
  "Test Goal Audio",
  "Test Penalty Audio",
  "Test Horn Audio",
  "Test Intermission Audio",
]) {
  if (!text.includes(required)) {
    throw new Error(
      `19.9 verification failed: ${required}`,
    );
  }
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 19.9 — Audio test controls and readiness

The Broadcast Session operator panel now includes local audio test controls.

Tests are available for:

- goal audio
- penalty audio
- horn audio
- intermission-complete audio

These tests play the configured URL directly in the operator browser. They do **not** emit `scoreboard:sound`, create a game event, alter score, or mutate broadcast/game state.

Audio readiness reports:

- `Audio disabled` when audio is intentionally muted
- `Audio not ready` when audio is enabled with no configured sound URLs
- `Audio ready` when at least one sound source is configured

Browser autoplay or media playback failure is isolated from SportsOS state and operator controls.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.9 audio test controls / broadcast readiness", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides direct operator audio testing", () => {
    expect(panel).toContain(
      "function testAudioUrl",
    );

    expect(panel).toContain(
      "new Audio(",
    );

    expect(panel).toContain(
      "audio.play().catch",
    );
  });

  it("provides test controls for every supported sound", () => {
    for (const label of [
      "Test Goal Audio",
      "Test Penalty Audio",
      "Test Horn Audio",
      "Test Intermission Audio",
    ]) {
      expect(panel).toContain(
        label,
      );
    }
  });

  it("calculates audio readiness without generating game events", () => {
    expect(panel).toContain(
      "const audioReadiness",
    );

    expect(panel).toContain(
      '"Audio disabled"',
    );

    expect(panel).toContain(
      '"Audio not ready"',
    );

    expect(panel).toContain(
      '"Audio ready"',
    );

    expect(panel).not.toContain(
      'socket.emit("scoreboard:sound"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - local goal audio test"
echo "  - local penalty audio test"
echo "  - local horn audio test"
echo "  - local intermission audio test"
echo "  - Audio disabled / not ready / ready summary"
echo "  - no scoreboard/game event generated by tests"
echo "  - playback failure isolation"
echo "  - Milestone 19.9 regression tests"
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
echo "  Milestone 19.10 - Broadcast Operations Acceptance / Closeout"
