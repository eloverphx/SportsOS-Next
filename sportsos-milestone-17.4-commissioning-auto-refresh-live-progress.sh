#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.4-commissioning-live-progress-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx"
TEST="packages/core/test/commissioning-live-progress-17.4.test.ts"

for required in \
  ".git" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    "useEffect",
  )
) {
  text =
    text.replace(
`import {
  useCallback,
  useMemo,
  useState,
} from "react";`,
`import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";`
    );
} else {
  if (!text.includes("useRef")) {
    text =
      text.replace(
        'useEffect,',
        'useEffect,\n  useRef,',
      );
  }
}

if (
  !text.includes(
    "COMMISSIONING_AUTO_REFRESH_MS",
  )
) {
  const anchor =
`const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate API_BASE.",
    );
  }

  text =
    text.replace(
      anchor,
`${anchor}

const COMMISSIONING_AUTO_REFRESH_MS =
  5000;`
    );
}

if (
  !text.includes(
    "autoRefreshEnabled",
  )
) {
  const anchor =
`  const [busy, setBusy] =
    useState(false);`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate busy state.",
    );
  }

  text =
    text.replace(
      anchor,
`${anchor}

  const [
    autoRefreshEnabled,
    setAutoRefreshEnabled,
  ] =
    useState(true);

  const validationInFlight =
    useRef(false);`
    );
}

if (
  !text.includes(
    "validateCommissioningSilently",
  )
) {
  const anchor =
`  async function runValidation() {`;

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate runValidation().",
    );
  }

  const helper =
`  const validateCommissioningSilently =
    useCallback(
      async (
        targetDeviceId:
          string,
      ) => {
        if (
          validationInFlight.current
        ) {
          return;
        }

        validationInFlight.current =
          true;

        try {
          const response =
            await fetch(
              \`\${API_BASE}/scoreboard-device-commissioning/\${encodeURIComponent(targetDeviceId)}/validate\`,
              {
                method:
                  "POST",
              },
            );

          if (!response.ok) {
            return;
          }

          const json =
            await response.json();

          setCommissioning(
            json?.data?.commissioning ??
            null,
          );
        } finally {
          validationInFlight.current =
            false;
        }
      },
      [],
    );

`;

  text =
    text.slice(0, idx) +
    helper +
    text.slice(idx);
}

if (
  !text.includes(
    "Commissioning live progress loop",
  )
) {
  const anchor =
`  return (`;

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate component return.",
    );
  }

  const effect =
`  // Commissioning live progress loop
  useEffect(() => {
    if (
      !commissioning ||
      commissioning.status ===
        "GAME_READY" ||
      !autoRefreshEnabled
    ) {
      return;
    }

    const device =
      commissioning.deviceId;

    const timer =
      window.setInterval(
        () => {
          void validateCommissioningSilently(
            device,
          );
        },
        COMMISSIONING_AUTO_REFRESH_MS,
      );

    return () => {
      window.clearInterval(
        timer,
      );
    };
  }, [
    commissioning,
    autoRefreshEnabled,
    validateCommissioningSilently,
  ]);

`;

  text =
    text.slice(0, idx) +
    effect +
    text.slice(idx);
}

if (
  !text.includes(
    "Live Progress",
  )
) {
  const anchor =
`            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void refresh()
                }`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate wizard action buttons.",
    );
  }

  const replacement =
`            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                onClick={() =>
                  setAutoRefreshEnabled(
                    (current) =>
                      !current,
                  )
                }
                className="rounded border border-slate-700 px-3 py-2 text-xs"
              >
                Live Progress:{" "}
                {autoRefreshEnabled
                  ? "ON"
                  : "OFF"}
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void refresh()
                }`;

  text =
    text.replace(
      anchor,
      replacement,
    );
}

if (
  !text.includes(
    "Auto-validation every 5 seconds",
  )
) {
  const anchor =
`            <div className="text-sm text-slate-400">
              {completedCount}
              /
              {commissioning.steps.length}
              {" "}steps complete
            </div>`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate completion summary.",
    );
  }

  text =
    text.replace(
      anchor,
`${anchor}

            <div className="text-xs text-slate-500">
              {commissioning.status ===
                "GAME_READY"
                ? "Auto-validation complete."
                : autoRefreshEnabled
                  ? "Auto-validation every 5 seconds."
                  : "Auto-validation paused."}
            </div>`
    );
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

describe("Milestone 17.4 commissioning auto-refresh / live device progress", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("uses an automatic validation cadence", () => {
    expect(panel).toContain(
      "COMMISSIONING_AUTO_REFRESH_MS",
    );

    expect(panel).toContain(
      "5000",
    );

    expect(panel).toContain(
      "setInterval",
    );
  });

  it("re-runs server commissioning validation automatically", () => {
    expect(panel).toContain(
      "validateCommissioningSilently",
    );

    expect(panel).toContain(
      "/validate",
    );
  });

  it("prevents overlapping background validation requests", () => {
    expect(panel).toContain(
      "validationInFlight",
    );
  });

  it("stops live validation when the device becomes game ready", () => {
    expect(panel).toContain(
      'commissioning.status ===',
    );

    expect(panel).toContain(
      '"GAME_READY"',
    );
  });

  it("allows the operator to pause live progress", () => {
    expect(panel).toContain(
      "Live Progress:",
    );

    expect(panel).toContain(
      "autoRefreshEnabled",
    );

    expect(panel).toContain(
      "Auto-validation paused.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - 5-second commissioning auto-validation"
echo "  - live enrollment/assignment/readiness/firmware progress"
echo "  - overlapping-request protection"
echo "  - automatic stop at GAME_READY"
echo "  - Live Progress ON/OFF operator control"
echo "  - live progress status text"
echo "  - Milestone 17.4 regression tests"
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
echo "  Milestone 17.5 - Commissioning Failure Guidance / Remediation Actions"
