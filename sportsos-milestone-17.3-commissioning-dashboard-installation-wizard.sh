#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.3-commissioning-dashboard-installation-wizard-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts" \
  "apps/api/src/services/scoreboardDeviceCommissioning.ts" \
  "apps/api/src/services/scoreboardCommissioningValidator.ts" \
  "apps/dashboard/app/scoreboards/operations/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

PANEL="apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx"
PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
TEST="packages/core/test/commissioning-dashboard-installation-wizard-17.3.test.ts"

for file in "$PANEL" "$PAGE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PANEL")" "$(dirname "$TEST")"

cat > "$PANEL" <<'EOF'
"use client";

import {
  useCallback,
  useMemo,
  useState,
} from "react";

type CommissioningStepId =
  | "FLASHED"
  | "PROVISIONED"
  | "ENROLLED"
  | "VERIFIED"
  | "ASSIGNED"
  | "CONNECTIVITY"
  | "READINESS"
  | "FIRMWARE"
  | "GAME_READY";

type CommissioningStep = {
  id: CommissioningStepId;
  complete: boolean;
  completedAt: string | null;
  note: string | null;
};

type CommissioningRecord = {
  deviceId: string;
  createdAt: string;
  updatedAt: string;
  status:
    | "IN_PROGRESS"
    | "BLOCKED"
    | "GAME_READY";
  steps: CommissioningStep[];
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

const STEP_LABELS:
  Record<
    CommissioningStepId,
    string
  > = {
    FLASHED:
      "Firmware Flashed",
    PROVISIONED:
      "Device Provisioned",
    ENROLLED:
      "SportsOS Enrollment",
    VERIFIED:
      "Verified Hardware",
    ASSIGNED:
      "Scoreboard Assignment",
    CONNECTIVITY:
      "Connectivity",
    READINESS:
      "Heartbeat Readiness",
    FIRMWARE:
      "Approved Firmware",
    GAME_READY:
      "Game Ready",
  };

export function ScoreboardCommissioningWizard() {
  const [deviceId, setDeviceId] =
    useState("");

  const [
    commissioning,
    setCommissioning,
  ] =
    useState<CommissioningRecord | null>(
      null,
    );

  const [busy, setBusy] =
    useState(false);

  const [error, setError] =
    useState<string | null>(
      null,
    );

  const completedCount =
    useMemo(
      () =>
        commissioning?.steps.filter(
          (step) =>
            step.complete,
        ).length ??
        0,
      [commissioning],
    );

  const loadRecord =
    useCallback(
      async (
        requestedDeviceId:
          string,
      ) => {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(requestedDeviceId)}`,
            {
              cache:
                "no-store",
            },
          );

        if (!response.ok) {
          throw new Error(
            `Commissioning load failed (${response.status}).`,
          );
        }

        const json =
          await response.json();

        const record =
          json?.data?.commissioning ??
          null;

        setCommissioning(
          record,
        );

        return record as
          | CommissioningRecord
          | null;
      },
      [],
    );

  async function startCommissioning() {
    const normalized =
      deviceId.trim();

    if (!normalized) {
      setError(
        "Enter a scoreboard device ID.",
      );
      return;
    }

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(normalized)}`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Commissioning start failed (${response.status}).`,
        );
      }

      setCommissioning(
        json?.data?.commissioning ??
        null,
      );

      setError(
        null,
      );
    } catch (startError) {
      setError(
        startError instanceof Error
          ? startError.message
          : "Unable to start commissioning.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function setManualStep(
    step:
      | "FLASHED"
      | "PROVISIONED",
    complete:
      boolean,
  ) {
    if (!commissioning) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(commissioning.deviceId)}/step`,
          {
            method:
              "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                step,
                complete,
                note:
                  complete
                    ? "Confirmed by installer."
                    : "Installer confirmation cleared.",
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Step update failed (${response.status}).`,
        );
      }

      setCommissioning(
        json?.data?.commissioning ??
        null,
      );

      setError(
        null,
      );
    } catch (stepError) {
      setError(
        stepError instanceof Error
          ? stepError.message
          : "Unable to update commissioning step.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function runValidation() {
    if (!commissioning) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(commissioning.deviceId)}/validate`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Validation failed (${response.status}).`,
        );
      }

      setCommissioning(
        json?.data?.commissioning ??
        null,
      );

      setError(
        null,
      );
    } catch (validationError) {
      setError(
        validationError instanceof Error
          ? validationError.message
          : "Unable to validate commissioning.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function refresh() {
    if (!commissioning) {
      return;
    }

    setBusy(
      true,
    );

    try {
      await loadRecord(
        commissioning.deviceId,
      );

      setError(
        null,
      );
    } catch (refreshError) {
      setError(
        refreshError instanceof Error
          ? refreshError.message
          : "Unable to refresh commissioning record.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Scoreboard Commissioning
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Guided installation workflow from flashed controller to GAME_READY.
          </p>
        </div>

        {commissioning && (
          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-semibold">
            {commissioning.status}
          </span>
        )}
      </div>

      {!commissioning ? (
        <div className="mt-5 flex flex-col gap-3 sm:flex-row">
          <input
            value={deviceId}
            onChange={(event) =>
              setDeviceId(
                event.target.value,
              )
            }
            placeholder="Scoreboard device ID"
            className="min-w-0 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />

          <button
            type="button"
            disabled={busy}
            onClick={() =>
              void startCommissioning()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Start Commissioning
          </button>
        </div>
      ) : (
        <>
          <div className="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-800 p-4">
            <div>
              <div className="text-xs text-slate-500">
                Device
              </div>
              <div className="mt-1 font-mono text-sm">
                {commissioning.deviceId}
              </div>
            </div>

            <div className="text-sm text-slate-400">
              {completedCount}
              /
              {commissioning.steps.length}
              {" "}steps complete
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void refresh()
                }
                className="rounded border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Refresh
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void runValidation()
                }
                className="rounded border border-slate-700 px-3 py-2 text-xs font-medium disabled:opacity-50"
              >
                Run Validation
              </button>
            </div>
          </div>

          <div className="mt-4 space-y-2">
            {commissioning.steps.map(
              (step) => (
                <div
                  key={step.id}
                  className="rounded-lg border border-slate-800 p-4"
                >
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <div className="font-medium">
                        {STEP_LABELS[step.id]}
                      </div>
                      <div className="mt-1 text-xs text-slate-500">
                        {step.id}
                      </div>
                    </div>

                    <span className="rounded border border-slate-700 px-2 py-1 text-xs font-semibold">
                      {step.complete
                        ? "PASS"
                        : "PENDING"}
                    </span>
                  </div>

                  {step.note && (
                    <p className="mt-2 text-sm text-slate-400">
                      {step.note}
                    </p>
                  )}

                  {step.completedAt && (
                    <p className="mt-1 text-xs text-slate-500">
                      Completed {step.completedAt}
                    </p>
                  )}

                  {(step.id ===
                    "FLASHED" ||
                    step.id ===
                      "PROVISIONED") && (
                    <div className="mt-3 flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={
                          busy ||
                          step.complete
                        }
                        onClick={() =>
                          void setManualStep(
                            step.id,
                            true,
                          )
                        }
                        className="rounded border border-slate-700 px-3 py-1 text-xs disabled:opacity-50"
                      >
                        Confirm Complete
                      </button>

                      <button
                        type="button"
                        disabled={
                          busy ||
                          !step.complete
                        }
                        onClick={() =>
                          void setManualStep(
                            step.id,
                            false,
                          )
                        }
                        className="rounded border border-slate-800 px-3 py-1 text-xs disabled:opacity-50"
                      >
                        Clear
                      </button>
                    </div>
                  )}
                </div>
              ),
            )}
          </div>

          {commissioning.status ===
            "GAME_READY" && (
            <div className="mt-5 rounded-xl border border-slate-700 p-5">
              <div className="text-lg font-semibold">
                GAME_READY
              </div>
              <p className="mt-1 text-sm text-slate-400">
                This scoreboard controller has passed the full commissioning workflow.
              </p>
            </div>
          )}

          <button
            type="button"
            disabled={busy}
            onClick={() => {
              setCommissioning(
                null,
              );
              setDeviceId(
                "",
              );
              setError(
                null,
              );
            }}
            className="mt-4 rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
          >
            Commission Another Device
          </button>
        </>
      )}

      {error && (
        <p className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </p>
      )}
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { ScoreboardCommissioningWizard } from "./ScoreboardCommissioningWizard";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard operations imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "<ScoreboardCommissioningWizard />",
  )
) {
  const policyPanel =
    "<PhysicalControlPolicyPanel />";

  if (
    text.includes(
      policyPanel,
    )
  ) {
    text =
      text.replace(
        policyPanel,
        `<ScoreboardCommissioningWizard />
      ${policyPanel}`,
      );
  } else {
    const close =
      text.lastIndexOf(
        "</main>",
      );

    if (close === -1) {
      throw new Error(
        "Unable to locate scoreboard operations insertion point.",
      );
    }

    text =
      text.slice(
        0,
        close,
      ) +
      "      <ScoreboardCommissioningWizard />\n" +
      text.slice(
        close,
      );
  }
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

describe("Milestone 17.3 commissioning dashboard / installation wizard", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx",
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

  it("starts a commissioning record by device ID", () => {
    expect(panel).toContain(
      "Start Commissioning",
    );

    expect(panel).toContain(
      "/scoreboard-device-commissioning/",
    );
  });

  it("shows every commissioning step", () => {
    for (const step of [
      "FLASHED",
      "PROVISIONED",
      "ENROLLED",
      "VERIFIED",
      "ASSIGNED",
      "CONNECTIVITY",
      "READINESS",
      "FIRMWARE",
      "GAME_READY",
    ]) {
      expect(panel).toContain(
        step,
      );
    }
  });

  it("allows only physical installation confirmations to be manually toggled", () => {
    expect(panel).toContain(
      'step.id ===\n                    "FLASHED"',
    );

    expect(panel).toContain(
      'step.id ===\n                      "PROVISIONED"',
    );

    expect(panel).toContain(
      "Confirm Complete",
    );
  });

  it("runs automated validation from the wizard", () => {
    expect(panel).toContain(
      "/validate",
    );

    expect(panel).toContain(
      "Run Validation",
    );
  });

  it("surfaces final game-ready state", () => {
    expect(panel).toContain(
      "GAME_READY",
    );

    expect(panel).toContain(
      "passed the full commissioning workflow",
    );
  });

  it("renders the wizard on scoreboard operations", () => {
    expect(page).toContain(
      "ScoreboardCommissioningWizard",
    );

    expect(page).toContain(
      "<ScoreboardCommissioningWizard />",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Scoreboard Commissioning installation wizard"
echo "  - device-ID commissioning start"
echo "  - full FLASHED -> GAME_READY step display"
echo "  - manual FLASHED / PROVISIONED confirmations"
echo "  - automatic validation action"
echo "  - per-step notes and timestamps"
echo "  - GAME_READY completion surface"
echo "  - commission-another-device workflow"
echo "  - Milestone 17.3 regression tests"
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
echo "  Milestone 17.4 - Commissioning Auto-Refresh / Live Device Progress"
