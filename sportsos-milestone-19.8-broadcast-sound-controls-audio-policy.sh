#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.8-broadcast-sound-policy-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionProfile.ts"
ROUTE="apps/api/src/routes/broadcastSessionProfiles.ts"
CORE="packages/core/src/contracts/realtime.ts"
PANEL="apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx"
OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
TEST="packages/core/test/broadcast-sound-policy-19.8.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for required in \
  ".git" \
  "$SERVICE" \
  "$ROUTE" \
  "$CORE" \
  "$PANEL" \
  "$OVERLAY"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$CORE" "$PANEL" "$OVERLAY" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/services/broadcastSessionProfile.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("soundEnabled:")) {
  text = text.replace(
`  sponsorRotationSeconds: number;
  updatedAt: string;`,
`  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;`
  );
}

if (!text.includes("soundEnabled?:")) {
  text = text.replace(
`  sponsorRotationSeconds?: number;
}): BroadcastSessionProfile {`,
`  sponsorRotationSeconds?: number;
  soundEnabled?: boolean;
  goalSoundUrl?: string | null;
  penaltySoundUrl?: string | null;
  hornSoundUrl?: string | null;
  intermissionSoundUrl?: string | null;
}): BroadcastSessionProfile {`
  );
}

if (!text.includes("normalizeOptionalUrl")) {
  const marker = "export function upsertBroadcastSessionProfile(input: {";
  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error("Unable to locate broadcast profile upsert.");
  }

  const helper =
`function normalizeOptionalUrl(
  value: string | null | undefined,
  fallback: string | null,
): string | null {
  if (value === undefined) {
    return fallback;
  }

  if (value === null) {
    return null;
  }

  return value.trim() || null;
}

`;

  text =
    text.slice(0, idx) +
    helper +
    text.slice(idx);
}

if (!text.includes("goalSoundUrl:")) {
  throw new Error("Sound profile fields were not added.");
}

if (!text.includes("soundEnabled:") || !text.includes("existing?.soundEnabled")) {
  text = text.replace(
`      sponsorRotationSeconds:
        rotationSeconds,
      updatedAt:`,
`      sponsorRotationSeconds:
        rotationSeconds,
      soundEnabled:
        input.soundEnabled ??
        existing?.soundEnabled ??
        false,
      goalSoundUrl:
        normalizeOptionalUrl(
          input.goalSoundUrl,
          existing?.goalSoundUrl ??
            null,
        ),
      penaltySoundUrl:
        normalizeOptionalUrl(
          input.penaltySoundUrl,
          existing?.penaltySoundUrl ??
            null,
        ),
      hornSoundUrl:
        normalizeOptionalUrl(
          input.hornSoundUrl,
          existing?.hornSoundUrl ??
            null,
        ),
      intermissionSoundUrl:
        normalizeOptionalUrl(
          input.intermissionSoundUrl,
          existing?.intermissionSoundUrl ??
            null,
        ),
      updatedAt:`
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/broadcastSessionProfiles.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("soundEnabled?:")) {
  text = text.replace(
`          sponsorRotationSeconds?: number;
        };`,
`          sponsorRotationSeconds?: number;
          soundEnabled?: boolean;
          goalSoundUrl?: string | null;
          penaltySoundUrl?: string | null;
          hornSoundUrl?: string | null;
          intermissionSoundUrl?: string | null;
        };`
  );
}

if (!text.includes("goalSoundUrl:")) {
  text = text.replace(
`          sponsorRotationSeconds:
            body.sponsorRotationSeconds,
        });`,
`          sponsorRotationSeconds:
            body.sponsorRotationSeconds,
          soundEnabled:
            body.soundEnabled,
          goalSoundUrl:
            body.goalSoundUrl,
          penaltySoundUrl:
            body.penaltySoundUrl,
          hornSoundUrl:
            body.hornSoundUrl,
          intermissionSoundUrl:
            body.intermissionSoundUrl,
        });`
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "packages/core/src/contracts/realtime.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("soundEnabled:")) {
  text = text.replace(
`  sponsorRotationSeconds: number;
  updatedAt: string;
}`,
`  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;
}`
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("soundEnabled:")) {
  text = text.replace(
`  sponsorRotationSeconds: number;
  updatedAt: string;
};`,
`  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;
};`
  );
}

if (!text.includes("const [soundEnabled")) {
  const marker = `  const [sponsorRotationSeconds, setSponsorRotationSeconds] = useState(10);`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate sponsor rotation state.");
  }

  text = text.replace(
    marker,
`${marker}
  const [soundEnabled, setSoundEnabled] = useState(false);
  const [goalSoundUrl, setGoalSoundUrl] = useState("");
  const [penaltySoundUrl, setPenaltySoundUrl] = useState("");
  const [hornSoundUrl, setHornSoundUrl] = useState("");
  const [intermissionSoundUrl, setIntermissionSoundUrl] = useState("");`
  );
}

if (!text.includes("setSoundEnabled(nextProfile")) {
  text = text.replace(
`      setSponsorRotationSeconds(
        nextProfile?.sponsorRotationSeconds ?? 10,
      );`,
`      setSponsorRotationSeconds(
        nextProfile?.sponsorRotationSeconds ?? 10,
      );
      setSoundEnabled(
        nextProfile?.soundEnabled ?? false,
      );
      setGoalSoundUrl(
        nextProfile?.goalSoundUrl ?? "",
      );
      setPenaltySoundUrl(
        nextProfile?.penaltySoundUrl ?? "",
      );
      setHornSoundUrl(
        nextProfile?.hornSoundUrl ?? "",
      );
      setIntermissionSoundUrl(
        nextProfile?.intermissionSoundUrl ?? "",
      );`
  );
}

if (!text.includes("goalSoundUrl: goalSoundUrl")) {
  text = text.replace(
`              sponsorRotationSeconds,
            }),`,
`              sponsorRotationSeconds,
              soundEnabled,
              goalSoundUrl:
                goalSoundUrl.trim() || null,
              penaltySoundUrl:
                penaltySoundUrl.trim() || null,
              hornSoundUrl:
                hornSoundUrl.trim() || null,
              intermissionSoundUrl:
                intermissionSoundUrl.trim() || null,
            }),`
  );
}

if (!text.includes("setSoundEnabled(false)")) {
  text = text.replace(
`      setSponsorRotationSeconds(10);
      setError(null);`,
`      setSponsorRotationSeconds(10);
      setSoundEnabled(false);
      setGoalSoundUrl("");
      setPenaltySoundUrl("");
      setHornSoundUrl("");
      setIntermissionSoundUrl("");
      setError(null);`
  );
}

if (!text.includes("Broadcast Audio")) {
  const anchor = `      <div className="mt-4 grid gap-3 md:grid-cols-3">`;
  const idx = text.indexOf(anchor);

  if (idx === -1) {
    throw new Error("Unable to locate broadcast controls.");
  }

  const block =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Broadcast Audio
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Optional overlay audio triggered by SportsOS scoreboard sound events.
            </p>
          </div>

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={soundEnabled}
              onChange={(event) =>
                setSoundEnabled(
                  event.target.checked,
                )
              }
            />
            Audio enabled
          </label>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Goal sound URL
            </span>
            <input
              value={goalSoundUrl}
              onChange={(event) =>
                setGoalSoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../goal.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Penalty sound URL
            </span>
            <input
              value={penaltySoundUrl}
              onChange={(event) =>
                setPenaltySoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../penalty.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Horn sound URL
            </span>
            <input
              value={hornSoundUrl}
              onChange={(event) =>
                setHornSoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../horn.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Intermission sound URL
            </span>
            <input
              value={intermissionSoundUrl}
              onChange={(event) =>
                setIntermissionSoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../intermission.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        </div>
      </div>

`;

  text =
    text.slice(0, idx) +
    block +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/games/[id]/overlay/page.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("soundEnabled:")) {
  text = text.replace(
`  sponsorRotationSeconds: number;
  updatedAt: string;
};`,
`  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;
};`
  );
}

if (!text.includes("playBroadcastSound")) {
  const componentMarker = "export default function OverlayPage()";
  const idx = text.indexOf(componentMarker);

  if (idx === -1) {
    throw new Error("Unable to locate overlay component.");
  }

  const helper =
`function playBroadcastSound(
  url: string | null,
): void {
  if (!url) {
    return;
  }

  const audio =
    new Audio(
      url,
    );

  audio.preload =
    "auto";

  void audio.play().catch(
    () => {
      // Browser/OBS autoplay policy may reject playback.
      // Audio failure must never affect overlay rendering or game state.
    },
  );
}

`;

  text =
    text.slice(0, idx) +
    helper +
    text.slice(idx);
}

if (!text.includes('socket.on(\n      "scoreboard:sound"')) {
  const marker = `    socket.on(
      "scoreboard:effect",`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error("Unable to locate scoreboard effect listener.");
  }

  const listener =
`    socket.on(
      "scoreboard:sound",
      (payload) => {
        if (
          Number(
            payload.gameId,
          ) !==
          gameId ||
          !profile?.soundEnabled
        ) {
          return;
        }

        const url =
          payload.type ===
            "GOAL"
            ? profile.goalSoundUrl
            : payload.type ===
                "PENALTY"
              ? profile.penaltySoundUrl
              : payload.type ===
                  "HORN"
                ? profile.hornSoundUrl
                : profile.intermissionSoundUrl;

        playBroadcastSound(
          url,
        );
      },
    );

`;

  text =
    text.slice(0, idx) +
    listener +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 19.8 — Broadcast sound controls and audio policy

Broadcast-session profiles now include an explicit audio policy.

Audio is disabled by default.

When enabled, operators may configure URLs for:

- goal
- penalty
- horn
- intermission-complete

The overlay consumes the existing:

```text
scoreboard:sound
```

realtime channel and selects the configured sound by event type.

Playback failures caused by browser or OBS autoplay policy are ignored. Audio playback must never alter overlay state, game state, scoring, lifecycle, or scoreboard synchronization.

This milestone intentionally keeps sound sources configurable rather than embedding specific copyrighted media in the repository.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.8 broadcast sound controls / operator audio policy", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionProfile.ts",
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

  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("keeps broadcast audio disabled by default", () => {
    expect(service).toContain(
      "existing?.soundEnabled ??",
    );

    expect(service).toContain(
      "false",
    );
  });

  it("persists per-event sound URLs", () => {
    for (const field of [
      "goalSoundUrl",
      "penaltySoundUrl",
      "hornSoundUrl",
      "intermissionSoundUrl",
    ]) {
      expect(service).toContain(
        field,
      );
    }
  });

  it("provides operator audio controls", () => {
    expect(panel).toContain(
      "Broadcast Audio",
    );

    expect(panel).toContain(
      "Audio enabled",
    );

    expect(panel).toContain(
      "Goal sound URL",
    );

    expect(panel).toContain(
      "Horn sound URL",
    );
  });

  it("uses the existing scoreboard sound channel", () => {
    expect(overlay).toContain(
      '"scoreboard:sound"',
    );

    expect(overlay).toContain(
      "playBroadcastSound",
    );
  });

  it("does not let playback rejection break the overlay", () => {
    expect(overlay).toContain(
      "audio.play().catch",
    );

    expect(overlay).toContain(
      "Audio failure must never affect overlay rendering or game state.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - per-game broadcast audio enable/mute policy"
echo "  - goal sound URL"
echo "  - penalty sound URL"
echo "  - horn sound URL"
echo "  - intermission-complete sound URL"
echo "  - scoreboard:sound overlay playback"
echo "  - autoplay-failure isolation"
echo "  - Milestone 19.8 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 19.9 - Audio Test Controls / Broadcast Readiness Check"
