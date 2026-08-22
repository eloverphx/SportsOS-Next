#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.8-inline-countdown-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

FILE="$ROOT/apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $FILE" >&2
  exit 1
}

cd "$ROOT"

mkdir -p "$BACKUP/apps/dashboard/app/scoreboards/operations"
cp -a "$FILE" "$BACKUP/apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

/*
 * Remove any previously inserted derived countdown block.
 * We no longer depend on component-local derived variables.
 */
const startMarker =
  "  const remainingFreshnessMs =";

const endMarker =
  '            : "Preflight is fresh and within the normal game-start window.";';

while (true) {
  const start =
    text.indexOf(startMarker);

  if (start === -1) {
    break;
  }

  const end =
    text.indexOf(
      endMarker,
      start,
    );

  if (end === -1) {
    throw new Error(
      "Found partial 18.8 countdown block but could not locate its end.",
    );
  }

  text =
    text.slice(0, start) +
    text.slice(
      end +
        endMarker.length,
    );
}

/*
 * Replace the complete Start Window Guidance card instead of trying to
 * patch individual identifiers. This makes the UI self-contained.
 */
const heading =
  "              Start Window Guidance";

const headingIndex =
  text.indexOf(heading);

if (headingIndex === -1) {
  throw new Error(
    "Unable to locate Start Window Guidance card.",
  );
}

const cardStart =
  text.lastIndexOf(
    '      <div className="mt-5 rounded-xl border border-slate-800 p-4">',
    headingIndex,
  );

if (cardStart === -1) {
  throw new Error(
    "Unable to locate Start Window Guidance card start.",
  );
}

/*
 * Find the next sibling card/conditional after this card. The existing
 * generated card is immediately followed by the latest-preflight block.
 */
const nextSiblingCandidates = [
  "\n      {latest && (",
  "\n      {history.length > 0 && (",
  "\n      <div className=\"mt-5 rounded-xl border border-slate-800 p-4\">",
];

let cardEnd = -1;

for (const marker of nextSiblingCandidates) {
  const candidate =
    text.indexOf(
      marker,
      headingIndex + heading.length,
    );

  if (
    candidate !== -1 &&
    (
      cardEnd === -1 ||
      candidate < cardEnd
    )
  ) {
    cardEnd =
      candidate;
  }
}

if (cardEnd === -1) {
  throw new Error(
    "Unable to locate Start Window Guidance card end.",
  );
}

const replacement =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Start Window Guidance
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Live countdown until the latest passing preflight expires.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 font-mono text-sm font-semibold">
            {freshness?.expiresAt
              ? (() => {
                  const remainingSeconds =
                    Math.ceil(
                      Math.max(
                        0,
                        Date.parse(
                          freshness.expiresAt,
                        ) -
                          countdownNow,
                      ) /
                        1000,
                    );

                  const minutes =
                    Math.floor(
                      remainingSeconds /
                        60,
                    );

                  const seconds =
                    remainingSeconds %
                    60;

                  return \`\${String(
                    minutes,
                  ).padStart(
                    2,
                    "0",
                  )}:\${String(
                    seconds,
                  ).padStart(
                    2,
                    "0",
                  )}\`;
                })()
              : "--:--"}
          </span>
        </div>

        <p className="mt-3 text-sm text-slate-400">
          {!freshness
            ? "Run a game-day preflight before starting the game."
            : !freshness.fresh
              ? "Preflight is expired or invalid. Rerun it before game start."
              : freshness.expiresAt &&
                  Math.max(
                    0,
                    Date.parse(
                      freshness.expiresAt,
                    ) -
                      countdownNow,
                  ) <=
                    120000
                ? "Preflight is close to expiration. Rerun now to avoid a start delay."
                : freshness.expiresAt &&
                    Math.max(
                      0,
                      Date.parse(
                        freshness.expiresAt,
                      ) -
                        countdownNow,
                    ) <=
                      300000
                  ? "Preflight is still valid, but the start window is getting short."
                  : "Preflight is fresh and within the normal game-start window."}
        </p>

        {freshness?.fresh &&
          freshness.expiresAt && (
          <div className="mt-3 text-xs text-slate-500">
            Current passing preflight expires at{" "}
            {freshness.expiresAt}.
          </div>
        )}
      </div>`;

text =
  text.slice(0, cardStart) +
  replacement +
  text.slice(cardEnd);

/*
 * Hard fail if any of the old unresolved symbols survive.
 */
for (const symbol of [
  "remainingFreshnessSeconds",
  "remainingFreshnessMinutes",
  "remainingFreshnessRemainderSeconds",
  "preflightGuidance",
  "remainingFreshnessMs",
]) {
  if (text.includes(symbol)) {
    throw new Error(
      `Old unresolved countdown symbol still present: ${symbol}`,
    );
  }
}

fs.writeFileSync(
  file,
  text,
);

console.log(
  "18.8 countdown UI converted to direct inline expressions; no derived countdown identifiers remain.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.8 inline countdown repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - removes all five unresolved countdown identifiers"
echo "  - countdown now derives directly from freshness.expiresAt"
echo "  - guidance now derives directly from freshness + countdownNow"
echo "  - keeps 1-second live countdown behavior"
echo "  - eliminates component-scope dependency entirely"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
