#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.7-emergency-override-ui-audit-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/services/gameStartPreflightOverride.ts" \
  "apps/api/src/routes/gameDayHardwarePreflight.ts" \
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/gameStartPreflightOverride.ts"
ROUTE="apps/api/src/routes/gameDayHardwarePreflight.ts"
PANEL="apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
TEST="packages/core/test/emergency-override-ui-audit-18.7.test.ts"
DOC="docs/GAME-DAY-HARDWARE-PREFLIGHT.md"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/gameStartPreflightOverride.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("listGameStartPreflightOverrides")) {
  text += `

export function listGameStartPreflightOverrides(
  gameId?: string,
): GameStartPreflightOverride[] {
  return [...store.overrides]
    .filter(
      (item) =>
        !gameId ||
        item.gameId ===
          gameId,
    )
    .sort(
      (a, b) =>
        b.createdAt.localeCompare(
          a.createdAt,
        ),
    )
    .map(
      (item) => ({
        ...item,
        actorRoles:
          [...item.actorRoles],
      }),
    );
}
`;
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/gameDayHardwarePreflight.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("listGameStartPreflightOverrides")) {
  text =
    text.replace(
      'import { createGameStartPreflightOverride, revokeGameStartPreflightOverride } from "../services/gameStartPreflightOverride.js";',
      'import { createGameStartPreflightOverride, listGameStartPreflightOverrides, revokeGameStartPreflightOverride } from "../services/gameStartPreflightOverride.js";'
    );
}

if (
  !text.includes(
    "/game-day-hardware-preflight/:gameId/overrides"
  )
) {
  const marker =
    "export async function registerGameDayHardwarePreflightRoutes";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate preflight route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate preflight route body.",
    );
  }

  const route =
`
  app.get(
    "/game-day-hardware-preflight/:gameId/overrides",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          overrides:
            listGameStartPreflightOverrides(
              gameId,
            ),
        },
      };
    },
  );

`;

  text =
    text.slice(0, open + 1) +
    route +
    text.slice(open + 1);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("type EmergencyOverride")) {
  const marker =
    "type GameDayHardwarePreflight";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate preflight type.",
    );
  }

  text =
    text.slice(0, idx) +
`type EmergencyOverride = {
  overrideId: string;
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
  createdAt: string;
  expiresAt: string;
  revokedAt: string | null;
};

` +
    text.slice(idx);
}

if (!text.includes("overrideReason")) {
  const marker =
`  const [error, setError] =
    useState<string | null>(
      null,
    );`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate error state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    overrideReason,
    setOverrideReason,
  ] =
    useState("");

  const [
    overrides,
    setOverrides,
  ] =
    useState<EmergencyOverride[]>(
      [],
    );`
    );
}

if (!text.includes("loadOverrides")) {
  const marker =
`  const loadHistory =
    useCallback(`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate loadHistory callback.",
    );
  }

  const fn =
`  const loadOverrides =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setOverrides(
            [],
          );
          return;
        }

        const response =
          await fetch(
            \`\${API_BASE}/game-day-hardware-preflight/\${encodeURIComponent(normalized)}/overrides\`,
            {
              cache:
                "no-store",
            },
          );

        if (!response.ok) {
          return;
        }

        const json =
          await response.json();

        setOverrides(
          json?.data?.overrides ??
          [],
        );
      },
      [],
    );

`;

  text =
    text.slice(0, idx) +
    fn +
    text.slice(idx);
}

if (!text.includes("createEmergencyOverride")) {
  const marker =
`  async function runPreflight() {`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate runPreflight.",
    );
  }

  const fn =
`  async function createEmergencyOverride() {
    const normalizedGameId =
      gameId.trim();

    const normalizedReason =
      overrideReason.trim();

    const deviceId =
      latest?.deviceId;

    if (
      !normalizedGameId ||
      !deviceId ||
      !normalizedReason
    ) {
      setError(
        "A game, assigned device, and written override reason are required.",
      );
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          \`\${API_BASE}/game-day-hardware-preflight/\${encodeURIComponent(normalizedGameId)}/override\`,
          {
            method:
              "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                deviceId,
                reason:
                  normalizedReason,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          \`Emergency override failed (\${response.status}).\`,
        );
      }

      setOverrideReason(
        "",
      );

      setError(
        null,
      );

      await loadOverrides(
        normalizedGameId,
      );
    } catch (overrideError) {
      setError(
        overrideError instanceof Error
          ? overrideError.message
          : "Unable to create emergency override.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function revokeEmergencyOverride(
    overrideId:
      string,
  ) {
    const normalizedGameId =
      gameId.trim();

    if (!normalizedGameId) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          \`\${API_BASE}/game-day-hardware-preflight/\${encodeURIComponent(normalizedGameId)}/override/\${encodeURIComponent(overrideId)}\`,
          {
            method:
              "DELETE",
          },
        );

      if (!response.ok) {
        throw new Error(
          \`Override revocation failed (\${response.status}).\`,
        );
      }

      await loadOverrides(
        normalizedGameId,
      );
    } catch (revokeError) {
      setError(
        revokeError instanceof Error
          ? revokeError.message
          : "Unable to revoke emergency override.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

`;

  text =
    text.slice(0, idx) +
    fn +
    text.slice(idx);
}

if (
  !text.includes(
    "Emergency Start Override"
  )
) {
  const anchor =
`      {history.length > 0 && (`;

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate preflight history block.",
    );
  }

  const block =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div>
          <div className="font-semibold">
            Emergency Start Override
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Use only when operations must continue despite a blocked preflight. The original preflight result remains unchanged.
          </p>
        </div>

        <textarea
          value={overrideReason}
          onChange={(event) =>
            setOverrideReason(
              event.target.value,
            )
          }
          placeholder="Required emergency reason"
          rows={3}
          className="mt-3 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
        />

        <button
          type="button"
          disabled={
            busy ||
            !latest?.deviceId ||
            !overrideReason.trim()
          }
          onClick={() =>
            void createEmergencyOverride()
          }
          className="mt-3 rounded border border-slate-700 px-3 py-2 text-xs font-medium disabled:opacity-50"
        >
          Authorize Emergency Start
        </button>

        {overrides.length > 0 && (
          <div className="mt-4 space-y-2">
            {overrides.map(
              (item) => (
                <div
                  key={item.overrideId}
                  className="rounded border border-slate-800 p-3"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-mono text-xs">
                      {item.deviceId}
                    </span>
                    <span className="text-xs">
                      {item.revokedAt
                        ? "REVOKED"
                        : Date.parse(
                              item.expiresAt,
                            ) >
                            Date.now()
                          ? "ACTIVE"
                          : "EXPIRED"}
                    </span>
                  </div>

                  <p className="mt-2 text-sm text-slate-400">
                    {item.reason}
                  </p>

                  <div className="mt-2 text-xs text-slate-500">
                    Created {item.createdAt}
                    {" · "}
                    Expires {item.expiresAt}
                  </div>

                  <div className="mt-1 text-xs text-slate-500">
                    Actor:{" "}
                    {item.actorUserId ??
                      "authenticated operator"}
                    {item.actorRoles.length > 0
                      ? \` (\${item.actorRoles.join(", ")})\`
                      : ""}
                  </div>

                  {!item.revokedAt &&
                    Date.parse(
                      item.expiresAt,
                    ) >
                      Date.now() && (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        void revokeEmergencyOverride(
                          item.overrideId,
                        )
                      }
                      className="mt-3 rounded border border-slate-800 px-3 py-1 text-xs disabled:opacity-50"
                    >
                      Revoke Override
                    </button>
                  )}
                </div>
              ),
            )}
          </div>
        )}
      </div>

`;

  text =
    text.slice(0, idx) +
    block +
    text.slice(idx);
}

if (!text.includes("loadOverrides(normalized)")) {
  const timerBlock =
`          void loadHistory(
            normalized,
          );`;

  if (!text.includes(timerBlock)) {
    throw new Error(
      "Unable to locate gameId refresh effect.",
    );
  }

  text =
    text.replace(
      timerBlock,
`${timerBlock}
          void loadOverrides(
            normalized,
          );`
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Emergency override operator visibility

Milestone 18.7 exposes emergency authorization in the game-day preflight UI.

Operators can:

- enter a required written reason
- authorize an emergency start for the currently selected game/device
- see ACTIVE, EXPIRED, and REVOKED overrides
- see creation and expiration timestamps
- see recorded actor identity/roles when available
- revoke an active override

The UI clearly states that the original failed/expired preflight remains unchanged.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.7 emergency override UI / audit visibility", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightOverride.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("lists override audit history", () => {
    expect(service).toContain(
      "listGameStartPreflightOverrides",
    );

    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/overrides",
    );
  });

  it("requires a written reason in the UI", () => {
    expect(panel).toContain(
      "Required emergency reason",
    );

    expect(panel).toContain(
      "Authorize Emergency Start",
    );
  });

  it("shows active expired and revoked states", () => {
    expect(panel).toContain(
      '"ACTIVE"',
    );

    expect(panel).toContain(
      '"EXPIRED"',
    );

    expect(panel).toContain(
      '"REVOKED"',
    );
  });

  it("shows actor and expiration audit details", () => {
    expect(panel).toContain(
      "Actor:",
    );

    expect(panel).toContain(
      "Expires",
    );
  });

  it("allows explicit revocation", () => {
    expect(panel).toContain(
      "Revoke Override",
    );

    expect(panel).toContain(
      "revokeEmergencyOverride",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - emergency override audit-history API"
echo "  - required override reason UI"
echo "  - authorize emergency start action"
echo "  - ACTIVE / EXPIRED / REVOKED status"
echo "  - actor and expiration visibility"
echo "  - explicit revoke action"
echo "  - Milestone 18.7 regression tests"
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
echo "  Milestone 18.8 - Preflight Countdown / Start-Window Operator Guidance"
