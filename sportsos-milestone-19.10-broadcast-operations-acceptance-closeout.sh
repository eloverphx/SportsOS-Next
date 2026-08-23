#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.10-broadcast-operations-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

DOC="docs/BROADCAST-OPERATIONS-ACCEPTANCE.md"
STATUS="docs/MILESTONE-STATUS.md"
TEST="packages/core/test/broadcast-operations-acceptance-19.10.test.ts"

for required in \
  ".git" \
  "apps/api/src/services/broadcastSessionProfile.ts" \
  "apps/api/src/routes/broadcastSessionProfiles.ts" \
  "apps/dashboard/app/games/[id]/overlay/page.tsx" \
  "apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx" \
  "packages/core/src/contracts/realtime.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$DOC" "$STATUS" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")" docs

cat > "$DOC" <<'EOF'
# Broadcast Operations Acceptance

Milestone 19.10 closes the first production-style broadcast operations sequence.

## Acceptance boundary

SportsOS broadcast operations are presentation-only.

They must never become authoritative for:

- score
- clock
- period
- penalties
- teams
- lifecycle
- scoreboard assignment

Authoritative game state continues to come from the SportsOS API and public scoreboard snapshot.

## Broadcast session profile

Each game may have a persisted broadcast-session profile containing:

- enabled state
- title
- sponsor URL
- team-logo visibility
- power-play visibility
- scene preset
- sponsor rotation URLs
- sponsor rotation interval
- audio enabled state
- goal sound URL
- penalty sound URL
- horn sound URL
- intermission-complete sound URL

## Overlay configuration precedence

Presentation precedence is:

```text
temporary URL override
        ↓
persisted broadcast-session profile
        ↓
overlay default
```

URL overrides remain useful for testing and one-off presentation changes.

## Realtime requirements

Open overlays must update without manual refresh when the persisted broadcast profile changes.

Realtime events:

```text
broadcast-session:updated
broadcast-session:deleted
scoreboard:effect
scoreboard:sound
```

Public overlay clients subscribe to the existing:

```text
game:<gameId>
```

realtime room.

## Scene presets

Supported presets:

```text
STANDARD
MINIMAL
SPONSOR_FOCUS
```

STANDARD preserves the full scoreboard layout.

MINIMAL reduces presentation density.

SPONSOR_FOCUS keeps the game score visible while increasing sponsor prominence.

## Sponsor rotation

Broadcast profiles may include multiple sponsor URLs.

The overlay:

- rotates through configured sponsors
- uses the configured interval
- enforces a minimum interval
- resets cleanly when the profile changes

Sponsor rotation is presentation-only.

## Broadcast effects

The overlay consumes:

```text
scoreboard:effect
```

Supported effects:

```text
GOAL
PENALTY
PENALTY_ENDED
```

Effects are temporary visual treatments and automatically clear.

They do not create or modify scoring or penalty state.

## Broadcast audio

The overlay consumes:

```text
scoreboard:sound
```

Supported sound event types include:

```text
GOAL
PENALTY
HORN
INTERMISSION_COMPLETE
```

Audio is disabled by default.

Operators explicitly enable audio and configure media URLs.

Browser or OBS autoplay rejection must not affect overlay rendering, game state, or operator controls.

## Operator audio testing

The Broadcast Session panel provides local audio tests.

Audio tests:

- play only in the operator browser
- do not emit scoreboard sound events
- do not create game events
- do not alter game or broadcast state

## Operator acceptance sequence

Before a production broadcast:

1. Select the intended game.
2. Confirm the saved broadcast title.
3. Confirm team-logo and power-play visibility.
4. Select the intended scene preset.
5. Verify sponsor images and rotation.
6. Open the live overlay preview.
7. Confirm realtime branding changes appear without refresh.
8. If audio is enabled, confirm Audio Readiness reports ready.
9. Test each configured audio source locally.
10. Confirm game score, clock, period, and penalties continue to follow authoritative SportsOS state.
11. Confirm broadcast effects appear and clear without modifying game state.
12. Confirm reset returns presentation to overlay defaults.

## Validation gates

Required:

```bash
npm run typecheck && npm test
```

Runtime acceptance:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

For final Milestone 19 closeout, both validation gates must remain green.

## Closeout

Milestones 19.0 through 19.10 establish:

- repository continuation baseline
- persisted broadcast sessions
- overlay profile consumption
- operator broadcast controls
- realtime profile updates
- scene presets
- sponsor rotation
- goal/penalty effects
- audio policy
- local audio readiness/testing
- broadcast operations acceptance

Future broadcast work should extend these contracts rather than duplicate overlay, realtime, or game-state authority.
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "docs/MILESTONE-STATUS.md";

let text =
  fs.existsSync(file)
    ? fs.readFileSync(file, "utf8")
    : "# Milestone Status\n";

if (
  !text.includes(
    "### Milestone 19"
  )
) {
  text += `

### Milestone 19

Broadcast operations foundation:

- repository continuation baseline
- persisted broadcast-session profile
- overlay profile consumption
- operator broadcast-session UI
- realtime profile updates
- scene presets
- sponsor rotation
- goal and penalty presentation effects
- audio policy
- local audio test/readiness controls
- broadcast operations acceptance
`;
}

text =
  text.replace(
    /Milestone 19 next/g,
    "Milestone 19.10 complete",
  );

if (
  !text.includes(
    "Milestone 19.10 complete"
  )
) {
  text += `

## Current broadcast checkpoint

\`\`\`text
Milestone 19.10 complete
\`\`\`
`;
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.10 broadcast operations acceptance", () => {
  const acceptance =
    fs.readFileSync(
      new URL(
        "../../../docs/BROADCAST-OPERATIONS-ACCEPTANCE.md",
        import.meta.url,
      ),
      "utf8",
    );

  const profile =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("documents presentation-only authority boundary", () => {
    expect(
      acceptance,
    ).toContain(
      "presentation-only",
    );

    expect(
      acceptance,
    ).toContain(
      "Authoritative game state",
    );
  });

  it("retains persisted broadcast-session configuration", () => {
    expect(
      profile,
    ).toContain(
      "BroadcastSessionProfile",
    );

    expect(
      profile,
    ).toContain(
      "scenePreset",
    );

    expect(
      profile,
    ).toContain(
      "soundEnabled",
    );
  });

  it("retains realtime presentation updates", () => {
    expect(
      overlay,
    ).toContain(
      '"broadcast-session:updated"',
    );

    expect(
      overlay,
    ).toContain(
      '"scoreboard:effect"',
    );

    expect(
      overlay,
    ).toContain(
      '"scoreboard:sound"',
    );
  });

  it("retains sponsor rotation and scene presets", () => {
    expect(
      overlay,
    ).toContain(
      "Sponsor rotation timer",
    );

    expect(
      overlay,
    ).toContain(
      "data-scene-preset",
    );
  });

  it("retains operator preview and audio readiness", () => {
    expect(
      panel,
    ).toContain(
      "Open Live Overlay Preview",
    );

    expect(
      panel,
    ).toContain(
      "Audio Readiness",
    );

    expect(
      panel,
    ).toContain(
      "Test Goal Audio",
    );
  });

  it("documents final validation gates", () => {
    expect(
      acceptance,
    ).toContain(
      "npm run typecheck && npm test",
    );

    expect(
      acceptance,
    ).toContain(
      "npm run test:e2e:docker",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - broadcast operations acceptance document"
echo "  - authoritative presentation boundary"
echo "  - operator production-broadcast checklist"
echo "  - scene/sponsor/effect/audio acceptance criteria"
echo "  - Milestone 19 status closeout"
echo "  - closeout regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "FINAL MILESTONE 19 VALIDATION:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "After green:"
echo "  commit and tag Milestone 19."
