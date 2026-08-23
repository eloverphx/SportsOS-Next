#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.7-broadcast-effect-presentation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
CSS="apps/dashboard/app/games/[id]/overlay/overlay.module.css"
TEST="packages/core/test/broadcast-effect-presentation-19.7.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for required in \
  ".git" \
  "$OVERLAY" \
  "$CSS" \
  "packages/core/src/contracts/realtime.ts"
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

if (
  text.includes(
    'import type { PublicScoreboardGame, ScoreboardPenalty } from "@sportsos/core";',
  )
) {
  text =
    text.replace(
      'import type { PublicScoreboardGame, ScoreboardPenalty } from "@sportsos/core";',
      'import type { BroadcastEffectPayload, PublicScoreboardGame, ScoreboardPenalty } from "@sportsos/core";',
    );
} else if (
  !text.includes(
    "BroadcastEffectPayload",
  )
) {
  throw new Error(
    "Unable to locate @sportsos/core type import.",
  );
}

if (
  !text.includes(
    "const [activeEffect, setActiveEffect]",
  )
) {
  const profileStateMarkers = [
    `  const [sponsorIndex, setSponsorIndex] =
    useState(0);`,
    `  const [profile, setProfile] =
    useState<BroadcastSessionProfile | null>(null);`,
    `  const [now, setNow] = useState(() => Date.now());`,
  ];

  let marker = null;

  for (
    const candidate of
      profileStateMarkers
  ) {
    if (
      text.includes(
        candidate,
      )
    ) {
      marker =
        candidate;
      break;
    }
  }

  if (!marker) {
    throw new Error(
      "Unable to locate overlay state insertion point.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}
  const [
    activeEffect,
    setActiveEffect,
  ] =
    useState<BroadcastEffectPayload | null>(
      null,
    );`,
    );
}

if (
  !text.includes(
    'socket.on("scoreboard:effect"',
  )
) {
  const subscriptionMarkers = [
    `    socket.on("game:penalties-updated", refresh);`,
    `    socket.on("broadcast-session:deleted",`,
  ];

  let marker =
    null;

  for (
    const candidate of
      subscriptionMarkers
  ) {
    const index =
      text.indexOf(
        candidate,
      );

    if (
      index !== -1
    ) {
      if (
        candidate.startsWith(
          '    socket.on("game:penalties',
        )
      ) {
        marker =
          candidate;
        break;
      }
    }
  }

  if (!marker) {
    throw new Error(
      "Unable to locate realtime subscription insertion point.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

    socket.on(
      "scoreboard:effect",
      (
        payload:
          BroadcastEffectPayload,
      ) => {
        if (
          Number(
            payload.gameId,
          ) !==
          gameId
        ) {
          return;
        }

        setActiveEffect(
          payload,
        );
      },
    );`,
    );
}

if (
  !text.includes(
    "Broadcast effect auto-clear",
  )
) {
  const timerMarkers = [
    `  // Sponsor rotation timer`,
    `  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);`,
  ];

  let idx =
    -1;

  for (
    const marker of
      timerMarkers
  ) {
    idx =
      text.indexOf(
        marker,
      );

    if (
      idx !== -1
    ) {
      break;
    }
  }

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate overlay effects insertion point.",
    );
  }

  const effect =
`  // Broadcast effect auto-clear
  useEffect(() => {
    if (!activeEffect) {
      return;
    }

    const durationMs =
      activeEffect.type ===
        "GOAL"
        ? 5000
        : 4000;

    const timer =
      window.setTimeout(
        () => {
          setActiveEffect(
            null,
          );
        },
        durationMs,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    activeEffect,
  ]);

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    effect +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "BroadcastEffectCard",
  )
) {
  const componentMarker =
    "export default function OverlayPage()";

  const idx =
    text.indexOf(
      componentMarker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate OverlayPage component.",
    );
  }

  const component =
`function BroadcastEffectCard({
  effect,
  game,
}: {
  effect:
    BroadcastEffectPayload;
  game:
    Game;
}) {
  const teamName =
    effect.side ===
      "home"
      ? game.homeTeamName
      : game.awayTeamName;

  const heading =
    effect.type ===
      "GOAL"
      ? "GOAL"
      : effect.type ===
          "PENALTY"
        ? "PENALTY"
        : "PENALTY ENDED";

  const detail =
    effect.type ===
      "GOAL"
      ? [
          effect.jerseyNumber
            ? \`#\${effect.jerseyNumber}\`
            : null,
          effect.playerName ??
            null,
        ]
          .filter(Boolean)
          .join(" ")
      : effect.type ===
          "PENALTY"
        ? [
            effect.jerseyNumber
              ? \`#\${effect.jerseyNumber}\`
              : null,
            effect.playerName ??
              null,
            effect.infraction ??
              null,
            effect.penaltyMinutes
              ? \`\${effect.penaltyMinutes} MIN\`
              : null,
          ]
            .filter(Boolean)
            .join(" · ")
        : teamName;

  return (
    <section
      className={
        \`\${styles.effectCard} \${styles[\`effect\${effect.type.replaceAll("_", "")}\`]}\`
      }
      data-effect-type={
        effect.type
      }
      data-effect-side={
        effect.side
      }
    >
      <span>
        {teamName}
      </span>
      <strong>
        {heading}
      </strong>
      {detail && (
        <small>
          {detail}
        </small>
      )}
    </section>
  );
}

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    component +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "<BroadcastEffectCard",
  )
) {
  const mainMarker =
`    >
      <section`;

  const idx =
    text.indexOf(
      mainMarker,
      text.indexOf(
        "return (",
      ),
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate overlay main content.",
    );
  }

  const insertAt =
    idx +
    "    >".length;

  const effectRender =
`
      {activeEffect && (
        <BroadcastEffectCard
          effect={
            activeEffect
          }
          game={
            game
          }
        />
      )}
`;

  text =
    text.slice(
      0,
      insertAt,
    ) +
    effectRender +
    text.slice(
      insertAt,
    );
}

for (
  const required of
    [
      'socket.on(\n      "scoreboard:effect"',
      "BroadcastEffectCard",
      "Broadcast effect auto-clear",
      'activeEffect.type ===\n        "GOAL"',
      'data-effect-type=',
    ]
) {
  if (
    !text.includes(
      required,
    )
  ) {
    throw new Error(
      `19.7 verification failed: ${required}`,
    );
  }
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$CSS" <<'EOF'

/* Milestone 19.7 broadcast effect presentation */

.effectCard {
  position: absolute;
  left: 50%;
  bottom: 148px;
  z-index: 20;
  min-width: min(620px, 82vw);
  transform: translateX(-50%);
  border-radius: 18px;
  padding: 18px 28px;
  text-align: center;
  background: rgba(5, 10, 20, 0.94);
  box-shadow: 0 18px 60px rgba(0, 0, 0, 0.48);
  animation: sportsosEffectEnter 240ms ease-out;
}

.effectCard span,
.effectCard small {
  display: block;
}

.effectCard span {
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  opacity: 0.78;
}

.effectCard strong {
  display: block;
  margin-top: 2px;
  font-size: clamp(2rem, 5vw, 4rem);
  line-height: 1;
  letter-spacing: 0.04em;
}

.effectCard small {
  margin-top: 8px;
  font-size: clamp(0.85rem, 2vw, 1.15rem);
  font-weight: 600;
}

.effectGOAL {
  border: 2px solid var(--home-primary, rgba(255, 255, 255, 0.45));
}

.effectPENALTY {
  border: 2px solid rgba(255, 190, 70, 0.72);
}

.effectPENALTYENDED {
  border: 2px solid rgba(110, 220, 150, 0.62);
}

.effectCard[data-effect-side="away"].effectGOAL {
  border-color: var(--away-primary, rgba(255, 255, 255, 0.45));
}

@keyframes sportsosEffectEnter {
  from {
    opacity: 0;
    transform: translate(-50%, 16px) scale(0.96);
  }

  to {
    opacity: 1;
    transform: translate(-50%, 0) scale(1);
  }
}

@media (max-width: 900px) {
  .effectCard {
    bottom: 118px;
    min-width: 88vw;
    padding: 14px 18px;
  }
}
EOF

cat >> "$DOC" <<'EOF'

## Milestone 19.7 — Goal and penalty effect presentation

The live overlay now consumes the existing:

```text
scoreboard:effect
```

realtime event.

Supported effect types:

- `GOAL`
- `PENALTY`
- `PENALTY_ENDED`

The overlay displays a temporary presentation card containing available team, player, jersey, infraction, and penalty-minute information.

Default display duration:

- goal: 5 seconds
- penalty / penalty ended: 4 seconds

Effects are presentation-only. They do not create, alter, or reconcile game state. Authoritative scoring and penalty state still come from the SportsOS game engine and public scoreboard snapshot.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.7 broadcast effect presentation", () => {
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

  it("consumes the existing scoreboard effect channel", () => {
    expect(
      overlay,
    ).toContain(
      '"scoreboard:effect"',
    );

    expect(
      overlay,
    ).toContain(
      "BroadcastEffectPayload",
    );
  });

  it("supports goal and penalty effect types", () => {
    expect(
      overlay,
    ).toContain(
      '"GOAL"',
    );

    expect(
      overlay,
    ).toContain(
      '"PENALTY"',
    );

    expect(
      overlay,
    ).toContain(
      '"PENALTY ENDED"',
    );
  });

  it("automatically clears presentation effects", () => {
    expect(
      overlay,
    ).toContain(
      "Broadcast effect auto-clear",
    );

    expect(
      overlay,
    ).toContain(
      "5000",
    );

    expect(
      overlay,
    ).toContain(
      "4000",
    );
  });

  it("renders effect metadata when available", () => {
    expect(
      overlay,
    ).toContain(
      "effect.playerName",
    );

    expect(
      overlay,
    ).toContain(
      "effect.infraction",
    );

    expect(
      overlay,
    ).toContain(
      "effect.penaltyMinutes",
    );
  });

  it("adds dedicated presentation styling", () => {
    expect(
      css,
    ).toContain(
      ".effectCard",
    );

    expect(
      css,
    ).toContain(
      ".effectGOAL",
    );

    expect(
      css,
    ).toContain(
      ".effectPENALTY",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - scoreboard:effect overlay listener"
echo "  - GOAL presentation card"
echo "  - PENALTY presentation card"
echo "  - PENALTY_ENDED presentation card"
echo "  - player/jersey/infraction metadata"
echo "  - automatic effect timeout"
echo "  - responsive effect styling"
echo "  - Milestone 19.7 regression tests"
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
echo "  Milestone 19.8 - Broadcast Sound Controls / Operator Audio Policy"
