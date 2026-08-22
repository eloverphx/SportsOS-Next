#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="15.2-operator-lockout-controls-ui"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/page.tsx" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlPolicy.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
TEST="packages/core/test/operator-lockout-controls-ui-15.2.test.ts"

for file in "$PANEL" "$PAGE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p "$(dirname "$PANEL")" "$(dirname "$TEST")"

cat > "$PANEL" <<'EOF'
"use client";

import {
  FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

type PolicyMode = "ENABLED" | "LOCKED";
type ScopeType = "GAME" | "DEVICE" | "GAME_DEVICE";

type Policy = {
  scopeType: ScopeType;
  gameId: string | null;
  deviceId: string | null;
  mode: PolicyMode;
  reason: string | null;
  updatedAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function PhysicalControlPolicyPanel() {
  const [policies, setPolicies] = useState<Policy[]>([]);
  const [scopeType, setScopeType] = useState<ScopeType>("GAME_DEVICE");
  const [gameId, setGameId] = useState("");
  const [deviceId, setDeviceId] = useState("");
  const [mode, setMode] = useState<PolicyMode>("LOCKED");
  const [reason, setReason] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadPolicies = useCallback(async () => {
    try {
      const response = await fetch(
        `${API_BASE}/scoreboard-control-policies`,
        { cache: "no-store" },
      );

      if (!response.ok) {
        throw new Error(`Policy load failed (${response.status}).`);
      }

      const json = await response.json();
      setPolicies(json?.data?.policies ?? []);
      setError(null);
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : "Unable to load physical control policies.",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadPolicies();
  }, [loadPolicies]);

  const scopeValid = useMemo(() => {
    if (scopeType === "GAME") return Boolean(gameId.trim());
    if (scopeType === "DEVICE") return Boolean(deviceId.trim());
    return Boolean(gameId.trim() && deviceId.trim());
  }, [scopeType, gameId, deviceId]);

  async function savePolicy(event: FormEvent) {
    event.preventDefault();

    if (!scopeValid) {
      setError("Complete the selected policy scope first.");
      return;
    }

    setSaving(true);

    try {
      const response = await fetch(
        `${API_BASE}/scoreboard-control-policies`,
        {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            scopeType,
            gameId: gameId.trim() || null,
            deviceId: deviceId.trim() || null,
            mode,
            reason: reason.trim() || null,
          }),
        },
      );

      const json = await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Policy update failed (${response.status}).`,
        );
      }

      setReason("");
      setError(null);
      await loadPolicies();
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to update physical control policy.",
      );
    } finally {
      setSaving(false);
    }
  }

  async function deletePolicy(policy: Policy) {
    setSaving(true);

    try {
      const response = await fetch(
        `${API_BASE}/scoreboard-control-policies`,
        {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            scopeType: policy.scopeType,
            gameId: policy.gameId,
            deviceId: policy.deviceId,
          }),
        },
      );

      const json = await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Policy delete failed (${response.status}).`,
        );
      }

      setError(null);
      await loadPolicies();
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Unable to delete physical control policy.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div>
        <h2 className="text-xl font-semibold">
          Physical Control Lockout
        </h2>
        <p className="mt-1 text-sm text-slate-400">
          Server-authoritative enable/lock controls for physical scoreboard inputs.
        </p>
      </div>

      <form
        onSubmit={savePolicy}
        className="mt-5 grid gap-4 lg:grid-cols-2"
      >
        <label className="grid gap-2 text-sm">
          <span className="text-slate-400">Scope</span>
          <select
            value={scopeType}
            onChange={(event) =>
              setScopeType(event.target.value as ScopeType)
            }
            className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="GAME">Game</option>
            <option value="DEVICE">Device</option>
            <option value="GAME_DEVICE">Game + Device</option>
          </select>
        </label>

        <label className="grid gap-2 text-sm">
          <span className="text-slate-400">Mode</span>
          <select
            value={mode}
            onChange={(event) =>
              setMode(event.target.value as PolicyMode)
            }
            className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="LOCKED">Locked</option>
            <option value="ENABLED">Enabled</option>
          </select>
        </label>

        {scopeType !== "DEVICE" && (
          <label className="grid gap-2 text-sm">
            <span className="text-slate-400">Game ID</span>
            <input
              value={gameId}
              onChange={(event) => setGameId(event.target.value)}
              placeholder="game-id"
              className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        )}

        {scopeType !== "GAME" && (
          <label className="grid gap-2 text-sm">
            <span className="text-slate-400">Device ID</span>
            <input
              value={deviceId}
              onChange={(event) => setDeviceId(event.target.value)}
              placeholder="scoreboard-device-id"
              className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        )}

        <label className="grid gap-2 text-sm lg:col-span-2">
          <span className="text-slate-400">Reason</span>
          <input
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            placeholder="Optional operator note"
            className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <div className="lg:col-span-2">
          <button
            type="submit"
            disabled={saving || !scopeValid}
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50"
          >
            {saving
              ? "Saving…"
              : mode === "LOCKED"
                ? "Apply Lock"
                : "Apply Enable"}
          </button>
        </div>
      </form>

      {error && (
        <p className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </p>
      )}

      <div className="mt-6">
        <h3 className="font-semibold">Active Policies</h3>

        {loading ? (
          <p className="mt-3 text-sm text-slate-500">
            Loading policies…
          </p>
        ) : policies.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No explicit physical-control policies. Default behavior is enabled.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">Scope</th>
                  <th className="pb-2 pr-4">Game</th>
                  <th className="pb-2 pr-4">Device</th>
                  <th className="pb-2 pr-4">Mode</th>
                  <th className="pb-2 pr-4">Reason</th>
                  <th className="pb-2">Action</th>
                </tr>
              </thead>
              <tbody>
                {policies.map((policy) => (
                  <tr
                    key={[
                      policy.scopeType,
                      policy.gameId,
                      policy.deviceId,
                    ].join(":")}
                    className="border-t border-slate-800"
                  >
                    <td className="py-3 pr-4">{policy.scopeType}</td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {policy.gameId ?? "—"}
                    </td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {policy.deviceId ?? "—"}
                    </td>
                    <td className="py-3 pr-4">{policy.mode}</td>
                    <td className="py-3 pr-4 text-slate-400">
                      {policy.reason ?? "—"}
                    </td>
                    <td className="py-3">
                      <button
                        type="button"
                        disabled={saving}
                        onClick={() => void deletePolicy(policy)}
                        className="rounded border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <p className="mt-5 text-xs text-slate-500">
        Dashboard state is informational only. The API policy store remains authoritative.
      </p>
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");
const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { PhysicalControlPolicyPanel } from "./PhysicalControlPolicyPanel";';

if (!text.includes(importLine)) {
  const imports = text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard operations import block.",
    );
  }
  text =
    text.replace(
      imports[0],
      imports[0] + importLine + "\n",
    );
}

if (!text.includes("<PhysicalControlPolicyPanel />")) {
  const diagnostics =
    "<PhysicalControlDiagnosticsPanel />";

  if (text.includes(diagnostics)) {
    text =
      text.replace(
        diagnostics,
        `<PhysicalControlPolicyPanel />
      ${diagnostics}`,
      );
  } else {
    const close = text.lastIndexOf("</main>");
    if (close === -1) {
      throw new Error(
        "Unable to locate scoreboard operations insertion point.",
      );
    }
    text =
      text.slice(0, close) +
      "      <PhysicalControlPolicyPanel />\n" +
      text.slice(close);
  }
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.2 operator lockout controls UI", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  const page = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("supports game device and combined policy scopes", () => {
    for (const scope of [
      "GAME",
      "DEVICE",
      "GAME_DEVICE",
    ]) {
      expect(panel).toContain(`"${scope}"`);
    }
  });

  it("supports enabled and locked operator modes", () => {
    expect(panel).toContain('"LOCKED"');
    expect(panel).toContain('"ENABLED"');
  });

  it("uses the server policy API for reads and writes", () => {
    expect(panel).toContain(
      "/scoreboard-control-policies",
    );
    expect(panel).toContain('method: "PUT"');
    expect(panel).toContain('method: "DELETE"');
  });

  it("does not use localStorage for authority", () => {
    expect(panel).not.toContain("localStorage");
  });

  it("shows active policies and removal controls", () => {
    expect(panel).toContain("Active Policies");
    expect(panel).toContain("Remove");
  });

  it("renders on scoreboard operations page", () => {
    expect(page).toContain(
      "PhysicalControlPolicyPanel",
    );
    expect(page).toContain(
      "<PhysicalControlPolicyPanel />",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Physical Control Lockout operator panel"
echo "  - GAME / DEVICE / GAME_DEVICE scope selection"
echo "  - ENABLED / LOCKED controls"
echo "  - optional operator reason"
echo "  - active policy table"
echo "  - policy removal"
echo "  - server API read/write only"
echo "  - no localStorage authority"
echo "  - Milestone 15.2 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 15.3 - Game Lifecycle Auto-Lock Policy"
