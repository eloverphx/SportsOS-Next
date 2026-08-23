#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.2-overlay-profile-consumption-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
TEST="packages/core/test/overlay-profile-consumption-19.2.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for required in \
  ".git" \
  "$OVERLAY" \
  "apps/api/src/routes/broadcastSessionProfiles.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$OVERLAY" "$TEST" "$DOC"; do
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

if (!text.includes("type BroadcastSessionProfile")) {
  const marker =
    "type Game = PublicScoreboardGame;";

  text =
    text.replace(
      marker,
`${marker}

type BroadcastSessionProfile = {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  updatedAt: string;
};`
    );
}

if (!text.includes("const [profile, setProfile]")) {
  const marker =
`  const [game, setGame] = useState<Game | null>(null);
  const [now, setNow] = useState(() => Date.now());`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate overlay state.");
  }

  text =
    text.replace(
      marker,
`${marker}
  const [profile, setProfile] =
    useState<BroadcastSessionProfile | null>(
      null,
    );`
    );
}

if (!text.includes("loadBroadcastProfile")) {
  const marker =
`  const load = useCallback(async () => {
    const response = await fetch(\`${API}/public/games/\${gameId}/scoreboard\`, { cache: "no-store" });
    const body = (await response.json()) as { game: Game };
    setGame(body.game);
  }, [gameId]);`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate overlay scoreboard loader.");
  }

  const addition =
`${marker}

  const loadBroadcastProfile =
    useCallback(async () => {
      const response =
        await fetch(
          \`${API}/public/games/\${gameId}/broadcast-session\`,
          {
            cache:
              "no-store",
          },
        );

      if (!response.ok) {
        setProfile(
          null,
        );
        return;
      }

      const body =
        (await response.json()) as {
          data?: {
            profile?: BroadcastSessionProfile | null;
          };
        };

      setProfile(
        body.data?.profile ??
        null,
      );
    }, [gameId]);`;

  text =
    text.replace(
      marker,
      addition,
    );
}

if (
  text.includes("void load();") &&
  !text.includes("void loadBroadcastProfile();")
) {
  text =
    text.replace(
`    void load();
    const socket = createRealtimeSocket(API);`,
`    void load();
    void loadBroadcastProfile();
    const socket = createRealtimeSocket(API);`
    );
}

if (
  text.includes("void load();") &&
  text.includes("connectedOnce") &&
  !text.includes("void loadBroadcastProfile();\n    });")
) {
  text =
    text.replace(
`      void load();
    });`,
`      void load();
      void loadBroadcastProfile();
    });`
    );
}

if (
  text.includes("}, [gameId, load]);")
) {
  text =
    text.replace(
      "}, [gameId, load]);",
      "}, [gameId, load, loadBroadcastProfile]);",
    );
}

if (!text.includes("const effectiveTitle")) {
  const marker =
`  if (!game) return null;

  const title = search.get("title") || game.organizationName;
  const sponsorUrl = search.get("sponsorUrl");`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate overlay presentation variables.");
  }

  const replacement =
`  if (!game) return null;

  const effectiveTitle =
    search.get("title") ??
    profile?.title ??
    game.organizationName;

  const effectiveSponsorUrl =
    search.get("sponsorUrl") ??
    profile?.sponsorUrl ??
    null;

  const showPowerPlay =
    search.get("showPowerPlay") === "0"
      ? false
      : search.get("showPowerPlay") === "1"
        ? true
        : profile?.showPowerPlay ??
          true;

  const showTeamLogos =
    search.get("showTeamLogos") === "0"
      ? false
      : search.get("showTeamLogos") === "1"
        ? true
        : profile?.showTeamLogos ??
          true;`;

  text =
    text.replace(
      marker,
      replacement,
    );
}

text =
  text.replace(
    "<Logo url={game.awayTeamLogoUrl} name={game.awayTeamName} />",
    "{showTeamLogos ? <Logo url={game.awayTeamLogoUrl} name={game.awayTeamName} /> : null}",
  );

text =
  text.replace(
    "<Logo url={game.homeTeamLogoUrl} name={game.homeTeamName} />",
    "{showTeamLogos ? <Logo url={game.homeTeamLogoUrl} name={game.homeTeamName} /> : null}",
  );

text =
  text.replace(
    "{powerPlay && <small>POWER PLAY · {powerPlay}</small>}",
    "{showPowerPlay && powerPlay && <small>POWER PLAY · {powerPlay}</small>}",
  );

text =
  text.replace(
    "<span>{title}</span>",
    "<span>{effectiveTitle}</span>",
  );

text =
  text.replace(
    "{sponsorUrl && <img src={sponsorUrl} alt=\"Sponsor\" />}",
    "{effectiveSponsorUrl && <img src={effectiveSponsorUrl} alt=\"Sponsor\" />}",
  );

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 19.2 — Overlay profile consumption

The broadcast overlay now loads the persisted public broadcast-session profile.

Presentation precedence is:

```text
URL override
    ↓
saved broadcast-session profile
    ↓
existing overlay default
```

Supported saved presentation settings:

- title
- sponsor URL
- power-play visibility
- team-logo visibility

URL query parameters remain available for temporary/test overrides:

```text
title
sponsorUrl
showPowerPlay=0|1
showTeamLogos=0|1
```

Game state remains sourced exclusively from the public scoreboard snapshot. Broadcast-session settings affect presentation only.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.2 overlay profile consumption", () => {
  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("loads the saved public broadcast-session profile", () => {
    expect(overlay).toContain(
      "/broadcast-session",
    );

    expect(overlay).toContain(
      "loadBroadcastProfile",
    );
  });

  it("uses saved title and sponsor settings", () => {
    expect(overlay).toContain(
      "profile?.title",
    );

    expect(overlay).toContain(
      "profile?.sponsorUrl",
    );
  });

  it("supports saved power-play and logo visibility", () => {
    expect(overlay).toContain(
      "profile?.showPowerPlay",
    );

    expect(overlay).toContain(
      "profile?.showTeamLogos",
    );
  });

  it("retains URL parameters as temporary overrides", () => {
    expect(overlay).toContain(
      'search.get("title")',
    );

    expect(overlay).toContain(
      'search.get("showPowerPlay")',
    );

    expect(overlay).toContain(
      'search.get("showTeamLogos")',
    );
  });

  it("continues to use the public scoreboard for game state", () => {
    expect(overlay).toContain(
      "/scoreboard",
    );

    expect(overlay).toContain(
      "PublicScoreboardGame",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - overlay loads persisted broadcast-session profile"
echo "  - saved title consumption"
echo "  - saved sponsor branding"
echo "  - saved power-play visibility"
echo "  - saved team-logo visibility"
echo "  - URL parameters remain temporary overrides"
echo "  - authoritative game state still comes from public scoreboard"
echo "  - Milestone 19.2 regression tests"
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
echo "  Milestone 19.3 - Broadcast Session Operator UI / Overlay Preview"
