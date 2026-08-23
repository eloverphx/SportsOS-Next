#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.6-scene-preset-styling-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
CSS="apps/dashboard/app/games/[id]/overlay/overlay.module.css"
TEST="packages/core/test/scene-preset-styling-19.6.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for required in \
  ".git" \
  "$OVERLAY" \
  "$CSS"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$OVERLAY" "$CSS" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/games/[id]/overlay/page.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("scenePreset === \"MINIMAL\"")) {
  text = text.replace(
`          <strong>{game.awayTeamName}</strong>`,
`          {scenePreset !== "MINIMAL" && (
            <strong>{game.awayTeamName}</strong>
          )}`
  );

  text = text.replace(
`          <strong>{game.homeTeamName}</strong>`,
`          {scenePreset !== "MINIMAL" && (
            <strong>{game.homeTeamName}</strong>
          )}`
  );
}

if (!text.includes("scenePreset !== \"SPONSOR_FOCUS\"")) {
  text = text.replace(
`          {showPowerPlay && powerPlay && <small>POWER PLAY · {powerPlay}</small>}`,
`          {scenePreset !== "SPONSOR_FOCUS" &&
            showPowerPlay &&
            powerPlay && (
              <small>
                POWER PLAY · {powerPlay}
              </small>
            )}`
  );
}

if (!text.includes("styles.sponsorFocus")) {
  text = text.replace(
`      <section className={styles.brandStrip}>`,
`      <section
        className={
          scenePreset === "SPONSOR_FOCUS"
            ? \`\${styles.brandStrip} \${styles.sponsorFocus}\`
            : styles.brandStrip
        }
      >`
  );
}

fs.writeFileSync(file, text);
NODE

cat >> "$CSS" <<'EOF'

/* Milestone 19.6 scene preset styling */

.bar[data-scene-preset="MINIMAL"] {
  max-width: 980px;
  margin-inline: auto;
}

.bar[data-scene-preset="MINIMAL"] .team {
  gap: 0.65rem;
}

.bar[data-scene-preset="MINIMAL"] .team strong {
  display: none;
}

.bar[data-scene-preset="MINIMAL"] .logo {
  width: 42px;
  height: 42px;
}

.bar[data-scene-preset="MINIMAL"] .center small {
  display: none;
}

.bar[data-scene-preset="SPONSOR_FOCUS"] {
  opacity: 0.92;
  transform: scale(0.96);
  transform-origin: bottom center;
}

.sponsorFocus {
  min-height: 96px;
  justify-content: center;
  gap: 2rem;
  font-size: 1.25rem;
}

.sponsorFocus img {
  max-height: 72px;
  max-width: 360px;
  object-fit: contain;
}

@media (max-width: 900px) {
  .sponsorFocus {
    min-height: 76px;
    font-size: 1rem;
  }

  .sponsorFocus img {
    max-height: 56px;
    max-width: 240px;
  }
}
EOF

cat >> "$DOC" <<'EOF'

## Milestone 19.6 — Scene preset styling

Scene presets now alter the visual presentation of the live overlay.

### STANDARD

Uses the existing full scoreboard presentation.

### MINIMAL

Reduces visual density by:

- hiding long team-name text
- using smaller logo treatment
- hiding secondary power-play text
- tightening the scoreboard footprint

### SPONSOR_FOCUS

Keeps the score visible while:

- slightly reducing the scoreboard bar emphasis
- enlarging the sponsor strip
- increasing sponsor image size
- hiding secondary power-play text

These presets change presentation only. Score, clock, period, penalties, and game lifecycle remain sourced from authoritative SportsOS game state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.6 scene preset styling", () => {
  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const css =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/overlay.module.css",
        import.meta.url,
      ),
      "utf8",
    );

  it("applies minimal presentation behavior", () => {
    expect(overlay).toContain(
      'scenePreset !== "MINIMAL"',
    );

    expect(css).toContain(
      '[data-scene-preset="MINIMAL"]',
    );
  });

  it("applies sponsor-focus presentation behavior", () => {
    expect(overlay).toContain(
      'scenePreset === "SPONSOR_FOCUS"',
    );

    expect(overlay).toContain(
      "styles.sponsorFocus",
    );

    expect(css).toContain(
      ".sponsorFocus",
    );
  });

  it("keeps authoritative game-state fields in the overlay", () => {
    expect(overlay).toContain(
      "game.homeScore",
    );

    expect(overlay).toContain(
      "game.awayScore",
    );

    expect(overlay).toContain(
      "game.clockRemainingMs",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - MINIMAL scene styling"
echo "  - SPONSOR_FOCUS scene styling"
echo "  - sponsor prominence layout"
echo "  - compact scoreboard layout"
echo "  - responsive sponsor-focus behavior"
echo "  - Milestone 19.6 regression tests"
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
echo "  Milestone 19.7 - Broadcast Effect Presets / Goal & Penalty Presentation"
