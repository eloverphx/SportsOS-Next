#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.5-broadcast-scene-presets-sponsor-rotation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

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

SERVICE="apps/api/src/services/broadcastSessionProfile.ts"
ROUTE="apps/api/src/routes/broadcastSessionProfiles.ts"
PANEL="apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx"
OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
CORE="packages/core/src/contracts/realtime.ts"
TEST="packages/core/test/broadcast-scene-presets-sponsor-rotation-19.5.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$OVERLAY" "$CORE" "$TEST" "$DOC"; do
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

if (!text.includes("export type BroadcastScenePreset")) {
  const marker = "export type BroadcastSessionProfile = {";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("BroadcastSessionProfile type missing.");

  text =
    text.slice(0, idx) +
`export type BroadcastScenePreset =
  | "STANDARD"
  | "MINIMAL"
  | "SPONSOR_FOCUS";

` +
    text.slice(idx);
}

if (!text.includes("scenePreset:")) {
  text = text.replace(
`  showTeamLogos: boolean;
  updatedAt: string;`,
`  showTeamLogos: boolean;
  scenePreset: BroadcastScenePreset;
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
  updatedAt: string;`
  );
}

if (!text.includes("scenePreset?:")) {
  text = text.replace(
`  showTeamLogos?: boolean;
}): BroadcastSessionProfile {`,
`  showTeamLogos?: boolean;
  scenePreset?: BroadcastScenePreset;
  sponsorUrls?: string[];
  sponsorRotationSeconds?: number;
}): BroadcastSessionProfile {`
  );
}

if (!text.includes("const normalizedSponsorUrls")) {
  const marker = `  const profile:
    BroadcastSessionProfile = {`;

  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Profile construction missing.");

  const setup = `  const normalizedSponsorUrls =
    Array.isArray(
      input.sponsorUrls,
    )
      ? input.sponsorUrls
          .map(
            (item) =>
              item.trim(),
          )
          .filter(Boolean)
      : existing?.sponsorUrls ??
        [];

  const rotationSeconds =
    Number.isFinite(
      input.sponsorRotationSeconds,
    ) &&
    Number(
      input.sponsorRotationSeconds,
    ) >= 3
      ? Math.floor(
          Number(
            input.sponsorRotationSeconds,
          ),
        )
      : existing?.sponsorRotationSeconds ??
        10;

`;

  text =
    text.slice(0, idx) +
    setup +
    text.slice(idx);
}

text = text.replace(
`      showTeamLogos:
        input.showTeamLogos ??
        existing?.showTeamLogos ??
        true,
      updatedAt:`,
`      showTeamLogos:
        input.showTeamLogos ??
        existing?.showTeamLogos ??
        true,
      scenePreset:
        input.scenePreset ??
        existing?.scenePreset ??
        "STANDARD",
      sponsorUrls:
        normalizedSponsorUrls,
      sponsorRotationSeconds:
        rotationSeconds,
      updatedAt:`
);

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/broadcastSessionProfiles.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("scenePreset?:")) {
  text = text.replace(
`          showTeamLogos?: boolean;
        };`,
`          showTeamLogos?: boolean;
          scenePreset?:
            | "STANDARD"
            | "MINIMAL"
            | "SPONSOR_FOCUS";
          sponsorUrls?: string[];
          sponsorRotationSeconds?: number;
        };`
  );
}

text = text.replace(
`          showTeamLogos:
            body.showTeamLogos,
        });`,
`          showTeamLogos:
            body.showTeamLogos,
          scenePreset:
            body.scenePreset,
          sponsorUrls:
            body.sponsorUrls,
          sponsorRotationSeconds:
            body.sponsorRotationSeconds,
        });`
);

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "packages/core/src/contracts/realtime.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("scenePreset:")) {
  text = text.replace(
`  showTeamLogos: boolean;
  updatedAt: string;
}`,
`  showTeamLogos: boolean;
  scenePreset:
    | "STANDARD"
    | "MINIMAL"
    | "SPONSOR_FOCUS";
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
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

if (!text.includes("scenePreset:")) {
  text = text.replace(
`  showTeamLogos: boolean;
  updatedAt: string;
};`,
`  showTeamLogos: boolean;
  scenePreset:
    | "STANDARD"
    | "MINIMAL"
    | "SPONSOR_FOCUS";
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
  updatedAt: string;
};`
  );
}

if (!text.includes("const [scenePreset")) {
  const marker = `  const [showTeamLogos, setShowTeamLogos] = useState(true);`;
  text = text.replace(
    marker,
`${marker}
  const [scenePreset, setScenePreset] =
    useState<"STANDARD" | "MINIMAL" | "SPONSOR_FOCUS">("STANDARD");
  const [sponsorUrlsText, setSponsorUrlsText] = useState("");
  const [sponsorRotationSeconds, setSponsorRotationSeconds] = useState(10);`
  );
}

if (!text.includes("setScenePreset(nextProfile")) {
  text = text.replace(
`      setShowTeamLogos(nextProfile?.showTeamLogos ?? true);`,
`      setShowTeamLogos(nextProfile?.showTeamLogos ?? true);
      setScenePreset(nextProfile?.scenePreset ?? "STANDARD");
      setSponsorUrlsText(
        (nextProfile?.sponsorUrls ?? []).join("\\n"),
      );
      setSponsorRotationSeconds(
        nextProfile?.sponsorRotationSeconds ?? 10,
      );`
  );
}

if (!text.includes("scenePreset,")) {
  text = text.replace(
`              showTeamLogos,
            }),`,
`              showTeamLogos,
              scenePreset,
              sponsorUrls:
                sponsorUrlsText
                  .split("\\n")
                  .map((item) => item.trim())
                  .filter(Boolean),
              sponsorRotationSeconds,
            }),`
  );
}

if (!text.includes("setScenePreset(\"STANDARD\")")) {
  text = text.replace(
`      setShowTeamLogos(true);
      setError(null);`,
`      setShowTeamLogos(true);
      setScenePreset("STANDARD");
      setSponsorUrlsText("");
      setSponsorRotationSeconds(10);
      setError(null);`
  );
}

if (!text.includes("Scene preset")) {
  const anchor = `      <div className="mt-4 grid gap-3 md:grid-cols-3">`;
  const idx = text.indexOf(anchor);
  if (idx === -1) throw new Error("Unable to locate presentation controls.");

  const block = `      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Scene preset
          </span>
          <select
            value={scenePreset}
            onChange={(event) =>
              setScenePreset(
                event.target.value as
                  | "STANDARD"
                  | "MINIMAL"
                  | "SPONSOR_FOCUS",
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="STANDARD">Standard</option>
            <option value="MINIMAL">Minimal</option>
            <option value="SPONSOR_FOCUS">Sponsor Focus</option>
          </select>
        </label>

        <label className="text-sm md:col-span-2">
          <span className="text-xs text-slate-500">
            Sponsor rotation URLs
          </span>
          <textarea
            value={sponsorUrlsText}
            onChange={(event) =>
              setSponsorUrlsText(
                event.target.value,
              )
            }
            rows={3}
            placeholder={"https://...\\nhttps://..."}
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Rotation seconds
          </span>
          <input
            type="number"
            min={3}
            value={sponsorRotationSeconds}
            onChange={(event) =>
              setSponsorRotationSeconds(
                Number(event.target.value) || 10,
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>
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

if (!text.includes("scenePreset:")) {
  text = text.replace(
`  showTeamLogos: boolean;
  updatedAt: string;
};`,
`  showTeamLogos: boolean;
  scenePreset:
    | "STANDARD"
    | "MINIMAL"
    | "SPONSOR_FOCUS";
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
  updatedAt: string;
};`
  );
}

if (!text.includes("const [sponsorIndex")) {
  const marker = `  const [profile, setProfile] =
    useState<BroadcastSessionProfile | null>(null);`;

  text = text.replace(
    marker,
`${marker}
  const [sponsorIndex, setSponsorIndex] =
    useState(0);`
  );
}

if (!text.includes("Sponsor rotation timer")) {
  const marker = `  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);`;

  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Overlay clock effect missing.");

  const effect = `  // Sponsor rotation timer
  useEffect(() => {
    const sponsors =
      profile?.sponsorUrls ??
      [];

    if (sponsors.length <= 1) {
      setSponsorIndex(0);
      return;
    }

    const seconds =
      Math.max(
        3,
        profile?.sponsorRotationSeconds ??
          10,
      );

    const timer =
      window.setInterval(
        () => {
          setSponsorIndex(
            (current) =>
              (current + 1) %
              sponsors.length,
          );
        },
        seconds * 1000,
      );

    return () => {
      window.clearInterval(timer);
    };
  }, [
    profile?.sponsorUrls,
    profile?.sponsorRotationSeconds,
  ]);

`;

  text =
    text.slice(0, idx) +
    effect +
    text.slice(idx);
}

if (!text.includes("rotatingSponsorUrl")) {
  const marker = `  const effectiveSponsorUrl =
    search.get("sponsorUrl") ??
    profile?.sponsorUrl ??
    null;`;

  if (!text.includes(marker)) throw new Error("Sponsor variable missing.");

  const replacement = `${marker}

  const rotatingSponsorUrl =
    profile?.sponsorUrls?.[
      sponsorIndex %
      Math.max(
        1,
        profile?.sponsorUrls?.length ??
          1,
      )
    ] ??
    effectiveSponsorUrl;

  const scenePreset =
    profile?.scenePreset ??
    "STANDARD";`;

  text = text.replace(marker, replacement);
}

text = text.replace(
`      <section className={styles.bar}>`,
`      <section
        className={styles.bar}
        data-scene-preset={scenePreset}
      >`
);

text = text.replace(
`        {effectiveSponsorUrl && <img src={effectiveSponsorUrl} alt="Sponsor" />}`,
`        {rotatingSponsorUrl && <img src={rotatingSponsorUrl} alt="Sponsor" />}`
);

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 19.5 — Scene presets and sponsor rotation foundation

Broadcast-session profiles now support:

- `STANDARD`
- `MINIMAL`
- `SPONSOR_FOCUS`

They also support a sponsor rotation list and configurable rotation interval.

The operator UI accepts one sponsor URL per line and a minimum rotation interval of 3 seconds.

The overlay rotates through saved sponsor URLs without altering authoritative game state. Scene preset is exposed on the overlay as `data-scene-preset` for presentation-specific styling in later milestones.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.5 broadcast scene presets / sponsor rotation foundation", () => {
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

  it("adds scene presets to broadcast profiles", () => {
    expect(service).toContain(
      '"STANDARD"',
    );
    expect(service).toContain(
      '"MINIMAL"',
    );
    expect(service).toContain(
      '"SPONSOR_FOCUS"',
    );
  });

  it("persists sponsor rotation configuration", () => {
    expect(service).toContain(
      "sponsorUrls",
    );
    expect(service).toContain(
      "sponsorRotationSeconds",
    );
  });

  it("provides operator controls", () => {
    expect(panel).toContain(
      "Scene preset",
    );
    expect(panel).toContain(
      "Sponsor rotation URLs",
    );
    expect(panel).toContain(
      "Rotation seconds",
    );
  });

  it("rotates sponsors in the overlay", () => {
    expect(overlay).toContain(
      "Sponsor rotation timer",
    );
    expect(overlay).toContain(
      "setSponsorIndex",
    );
    expect(overlay).toContain(
      "rotatingSponsorUrl",
    );
  });

  it("exposes scene preset to presentation styling", () => {
    expect(overlay).toContain(
      "data-scene-preset",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - STANDARD / MINIMAL / SPONSOR_FOCUS scene presets"
echo "  - sponsor rotation URL list"
echo "  - configurable sponsor rotation interval"
echo "  - operator controls"
echo "  - overlay sponsor rotation timer"
echo "  - scene preset presentation hook"
echo "  - Milestone 19.5 regression tests"
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
echo "  Milestone 19.6 - Scene Preset Styling / Sponsor Focus Presentation"
