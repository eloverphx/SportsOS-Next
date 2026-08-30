#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.2-literal-safe-overlay-profile-repair-${STAMP}"

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
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "type BroadcastSessionProfile"
  )
) {
  const marker =
    "type Game = PublicScoreboardGame;";

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate Game type.",
    );
  }

  text =
    text.replace(
      marker,
      marker +
      '\n\n' +
      'type BroadcastSessionProfile = {\n' +
      '  gameId: string;\n' +
      '  enabled: boolean;\n' +
      '  title: string | null;\n' +
      '  sponsorUrl: string | null;\n' +
      '  showPowerPlay: boolean;\n' +
      '  showTeamLogos: boolean;\n' +
      '  updatedAt: string;\n' +
      '};',
    );
}

if (
  !text.includes(
    "const [profile, setProfile]"
  )
) {
  const marker =
    '  const [now, setNow] = useState(() => Date.now());';

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate overlay now state.",
    );
  }

  text =
    text.replace(
      marker,
      marker +
      '\n' +
      '  const [profile, setProfile] =\n' +
      '    useState<BroadcastSessionProfile | null>(null);',
    );
}

if (
  !text.includes(
    "loadBroadcastProfile"
  )
) {
  const loadEndMarker =
    '  }, [gameId]);';

  const loadStart =
    text.indexOf(
      '  const load = useCallback(async () => {',
    );

  if (loadStart === -1) {
    throw new Error(
      "Unable to locate overlay scoreboard loader.",
    );
  }

  const loadEnd =
    text.indexOf(
      loadEndMarker,
      loadStart,
    );

  if (loadEnd === -1) {
    throw new Error(
      "Unable to locate overlay scoreboard loader end.",
    );
  }

  const insertAt =
    loadEnd +
    loadEndMarker.length;

  const addition =
    '\n\n' +
    '  const loadBroadcastProfile =\n' +
    '    useCallback(async () => {\n' +
    '      const response = await fetch(\n' +
    '        `${API}/public/games/${gameId}/broadcast-session`,\n' +
    '        { cache: "no-store" },\n' +
    '      );\n\n' +
    '      if (!response.ok) {\n' +
    '        setProfile(null);\n' +
    '        return;\n' +
    '      }\n\n' +
    '      const body =\n' +
    '        (await response.json()) as {\n' +
    '          data?: {\n' +
    '            profile?: BroadcastSessionProfile | null;\n' +
    '          };\n' +
    '        };\n\n' +
    '      setProfile(\n' +
    '        body.data?.profile ??\n' +
    '        null,\n' +
    '      );\n' +
    '    }, [gameId]);';

  text =
    text.slice(0, insertAt) +
    addition +
    text.slice(insertAt);
}

const firstLoad =
  '    void load();\n    const socket = createRealtimeSocket(API);';

if (
  text.includes(firstLoad) &&
  !text.includes(
    '    void load();\n    void loadBroadcastProfile();\n    const socket'
  )
) {
  text =
    text.replace(
      firstLoad,
      '    void load();\n' +
      '    void loadBroadcastProfile();\n' +
      '    const socket = createRealtimeSocket(API);',
    );
}

const reconnectLoad =
  '      void load();\n    });';

if (
  text.includes(reconnectLoad) &&
  !text.includes(
    '      void load();\n      void loadBroadcastProfile();\n    });'
  )
) {
  text =
    text.replace(
      reconnectLoad,
      '      void load();\n' +
      '      void loadBroadcastProfile();\n' +
      '    });',
    );
}

if (
  text.includes(
    '  }, [gameId, load]);'
  )
) {
  text =
    text.replace(
      '  }, [gameId, load]);',
      '  }, [gameId, load, loadBroadcastProfile]);',
    );
}

if (
  !text.includes(
    "const effectiveTitle"
  )
) {
  const oldPresentation =
    '  const title = search.get("title") || game.organizationName;\n' +
    '  const sponsorUrl = search.get("sponsorUrl");';

  if (!text.includes(oldPresentation)) {
    throw new Error(
      "Unable to locate existing title/sponsor presentation variables.",
    );
  }

  const replacement =
    '  const effectiveTitle =\n' +
    '    search.get("title") ??\n' +
    '    profile?.title ??\n' +
    '    game.organizationName;\n\n' +
    '  const effectiveSponsorUrl =\n' +
    '    search.get("sponsorUrl") ??\n' +
    '    profile?.sponsorUrl ??\n' +
    '    null;\n\n' +
    '  const showPowerPlay =\n' +
    '    search.get("showPowerPlay") === "0"\n' +
    '      ? false\n' +
    '      : search.get("showPowerPlay") === "1"\n' +
    '        ? true\n' +
    '        : profile?.showPowerPlay ?? true;\n\n' +
    '  const showTeamLogos =\n' +
    '    search.get("showTeamLogos") === "0"\n' +
    '      ? false\n' +
    '      : search.get("showTeamLogos") === "1"\n' +
    '        ? true\n' +
    '        : profile?.showTeamLogos ?? true;';

  text =
    text.replace(
      oldPresentation,
      replacement,
    );
}

text =
  text.replace(
    '<Logo url={game.awayTeamLogoUrl} name={game.awayTeamName} />',
    '{showTeamLogos ? <Logo url={game.awayTeamLogoUrl} name={game.awayTeamName} /> : null}',
  );

text =
  text.replace(
    '<Logo url={game.homeTeamLogoUrl} name={game.homeTeamName} />',
    '{showTeamLogos ? <Logo url={game.homeTeamLogoUrl} name={game.homeTeamName} /> : null}',
  );

text =
  text.replace(
    '{powerPlay && <small>POWER PLAY · {powerPlay}</small>}',
    '{showPowerPlay && powerPlay && <small>POWER PLAY · {powerPlay}</small>}',
  );

text =
  text.replace(
    '<span>{title}</span>',
    '<span>{effectiveTitle}</span>',
  );

text =
  text.replace(
    '{sponsorUrl && <img src={sponsorUrl} alt="Sponsor" />}',
    '{effectiveSponsorUrl && <img src={effectiveSponsorUrl} alt="Sponsor" />}',
  );

for (const required of [
  "type BroadcastSessionProfile",
  "loadBroadcastProfile",
  "/broadcast-session",
  "profile?.title",
  "profile?.sponsorUrl",
  "profile?.showPowerPlay",
  "profile?.showTeamLogos",
  "effectiveTitle",
  "effectiveSponsorUrl",
]) {
  if (!text.includes(required)) {
    throw new Error(
      `19.2 verification failed: ${required}`,
    );
  }
}

fs.writeFileSync(
  file,
  text,
);

console.log(
  "19.2 overlay profile consumption installed with literal-safe patching.",
);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 19.2 — Overlay profile consumption

The broadcast overlay loads the persisted public broadcast-session profile.

Presentation precedence:

```text
URL override
    ↓
saved broadcast-session profile
    ↓
existing overlay default
```

Supported settings:

- title
- sponsor URL
- power-play visibility
- team-logo visibility

Temporary query overrides remain supported:

```text
title
sponsorUrl
showPowerPlay=0|1
showTeamLogos=0|1
```

Authoritative game state continues to come only from the public scoreboard snapshot.
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

  it("loads persisted broadcast profile", () => {
    expect(overlay).toContain(
      "loadBroadcastProfile",
    );

    expect(overlay).toContain(
      "/broadcast-session",
    );
  });

  it("uses saved branding", () => {
    expect(overlay).toContain(
      "profile?.title",
    );

    expect(overlay).toContain(
      "profile?.sponsorUrl",
    );
  });

  it("uses saved visibility options", () => {
    expect(overlay).toContain(
      "profile?.showPowerPlay",
    );

    expect(overlay).toContain(
      "profile?.showTeamLogos",
    );
  });

  it("retains temporary query overrides", () => {
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

  it("keeps game state on public scoreboard source", () => {
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
echo " SportsOS-Next Milestone 19.2 repaired/installed"
echo "============================================================"
echo
echo "Fixed installer issue:"
echo "  - no Node evaluation of dashboard \${API} template literals"
echo
echo "Added:"
echo "  - persisted broadcast profile loading"
echo "  - saved title and sponsor"
echo "  - power-play visibility"
echo "  - team-logo visibility"
echo "  - temporary URL overrides retained"
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
