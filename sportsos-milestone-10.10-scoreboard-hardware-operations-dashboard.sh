#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.10-scoreboard-hardware-operations-dashboard"
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
  "$ROOT/apps" \
  "$ROOT/apps/dashboard"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

OPS_PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
OPS_CLIENT="apps/dashboard/components/scoreboards/ScoreboardHardwareOperationsDashboard.tsx"
LIB="apps/dashboard/lib/scoreboard-hardware-operations.ts"
TEST="apps/dashboard/test/scoreboard-hardware-operations-10.10.test.ts"

DEVICE_LIB="apps/dashboard/lib/scoreboard-devices.ts"
DEVICE_UI="apps/dashboard/components/scoreboards/ScoreboardDeviceOperations.tsx"

for file in "$DEVICE_LIB" "$DEVICE_UI"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required Milestone 10.5 file missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$OPS_PAGE")" \
  "$BACKUP_DIR/$(dirname "$OPS_CLIENT")" \
  "$BACKUP_DIR/$(dirname "$LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$OPS_PAGE")" \
  "$(dirname "$OPS_CLIENT")" \
  "$(dirname "$TEST")"

for file in "$OPS_PAGE" "$OPS_CLIENT" "$LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$LIB" <<'EOF'
import type {
  ScoreboardDeviceRuntime,
} from "./scoreboard-devices";

export type ScoreboardAssignment = {
  gameId: string;
  deviceId: string;
  assignedAt: string;
};

export type ScoreboardHardwareStage =
  | "NO_DEVICES"
  | "DEGRADED"
  | "READY"
  | "ACTIVE";

export type ScoreboardHardwareOperationsSummary = {
  stage: ScoreboardHardwareStage;
  discovered: number;
  online: number;
  assigned: number;
  activeGames: number;
  alerts: string[];
  readinessPercent: number;
};

export function buildScoreboardHardwareOperationsSummary(
  devices: ScoreboardDeviceRuntime[],
  assignments: ScoreboardAssignment[],
): ScoreboardHardwareOperationsSummary {
  const discovered = devices.length;

  const online = devices.filter(
    (device) =>
      device.presence?.online === true,
  ).length;

  const assigned = assignments.length;

  const activeGames = assignments.filter(
    (assignment) =>
      devices.some(
        (device) =>
          device.deviceId ===
            assignment.deviceId &&
          device.presence?.online === true &&
          device.state?.gameId ===
            assignment.gameId,
      ),
  ).length;

  const alerts: string[] = [];

  if (discovered === 0) {
    alerts.push(
      "No scoreboard devices have reported through MQTT.",
    );
  }

  if (
    discovered > 0 &&
    online < discovered
  ) {
    alerts.push(
      `${discovered - online} scoreboard device(s) are offline.`,
    );
  }

  for (const assignment of assignments) {
    const device = devices.find(
      (candidate) =>
        candidate.deviceId ===
        assignment.deviceId,
    );

    if (!device) {
      alerts.push(
        `Assigned device ${assignment.deviceId} has not been discovered.`,
      );
      continue;
    }

    if (!device.presence?.online) {
      alerts.push(
        `Assigned device ${assignment.deviceId} is offline.`,
      );
    }
  }

  let stage: ScoreboardHardwareStage =
    "NO_DEVICES";

  if (discovered > 0) {
    stage =
      online === discovered
        ? "READY"
        : "DEGRADED";
  }

  if (
    assigned > 0 &&
    activeGames === assigned &&
    online > 0
  ) {
    stage = "ACTIVE";
  }

  const checks = [
    discovered > 0,
    discovered > 0 && online === discovered,
    assigned === 0 || activeGames === assigned,
    alerts.length === 0,
  ];

  const readinessPercent =
    Math.round(
      (checks.filter(Boolean).length /
        checks.length) *
        100,
    );

  return {
    stage,
    discovered,
    online,
    assigned,
    activeGames,
    alerts,
    readinessPercent,
  };
}
EOF

cat > "$OPS_CLIENT" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  type ScoreboardDeviceRuntime,
  type ScoreboardDevicesResponse,
} from "../../lib/scoreboard-devices";
import {
  buildScoreboardHardwareOperationsSummary,
  type ScoreboardAssignment,
} from "../../lib/scoreboard-hardware-operations";
import {
  ScoreboardDeviceOperations,
} from "./ScoreboardDeviceOperations";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ??
  "";

type AssignmentsResponse = {
  success: boolean;
  data?: {
    assignments: ScoreboardAssignment[];
  };
};

async function loadDevices(): Promise<
  ScoreboardDeviceRuntime[]
> {
  const response = await fetch(
    `${API_BASE_URL}/scoreboard-devices`,
    {
      credentials: "include",
      cache: "no-store",
    },
  );

  if (!response.ok) {
    throw new Error(
      `Device request failed (${response.status}).`,
    );
  }

  const payload =
    (await response.json()) as ScoreboardDevicesResponse;

  return payload.data?.devices ?? [];
}

async function loadAssignments(): Promise<
  ScoreboardAssignment[]
> {
  const response = await fetch(
    `${API_BASE_URL}/scoreboard-devices/assignments`,
    {
      credentials: "include",
      cache: "no-store",
    },
  );

  if (!response.ok) {
    throw new Error(
      `Assignment request failed (${response.status}).`,
    );
  }

  const payload =
    (await response.json()) as AssignmentsResponse;

  return payload.data?.assignments ?? [];
}

export function ScoreboardHardwareOperationsDashboard() {
  const [devices, setDevices] = useState<
    ScoreboardDeviceRuntime[]
  >([]);
  const [assignments, setAssignments] =
    useState<ScoreboardAssignment[]>([]);
  const [gameId, setGameId] = useState("");
  const [deviceId, setDeviceId] =
    useState("");
  const [error, setError] =
    useState<string | null>(null);
  const [busy, setBusy] =
    useState(false);

  const load = useCallback(async () => {
    try {
      const [
        nextDevices,
        nextAssignments,
      ] = await Promise.all([
        loadDevices(),
        loadAssignments(),
      ]);

      setDevices(nextDevices);
      setAssignments(
        nextAssignments,
      );
      setError(null);
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : "Unable to load scoreboard hardware operations.",
      );
    }
  }, []);

  useEffect(() => {
    void load();

    const timer = window.setInterval(
      () => void load(),
      3000,
    );

    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  const summary = useMemo(
    () =>
      buildScoreboardHardwareOperationsSummary(
        devices,
        assignments,
      ),
    [
      assignments,
      devices,
    ],
  );

  const assign = async () => {
    if (
      !gameId.trim() ||
      !deviceId.trim()
    ) {
      setError(
        "Game ID and device ID are required.",
      );
      return;
    }

    setBusy(true);

    try {
      const response = await fetch(
        `${API_BASE_URL}/scoreboard-devices/assignments/${encodeURIComponent(
          gameId.trim(),
        )}`,
        {
          method: "PUT",
          credentials: "include",
          headers: {
            "Content-Type":
              "application/json",
          },
          body: JSON.stringify({
            deviceId:
              deviceId.trim(),
          }),
        },
      );

      if (!response.ok) {
        throw new Error(
          `Assignment failed (${response.status}).`,
        );
      }

      await load();
      setError(null);
    } catch (assignmentError) {
      setError(
        assignmentError instanceof Error
          ? assignmentError.message
          : "Unable to assign scoreboard.",
      );
    } finally {
      setBusy(false);
    }
  };

  const reconcile = async (
    targetDeviceId: string,
  ) => {
    setBusy(true);

    try {
      const response = await fetch(
        `${API_BASE_URL}/scoreboard-devices/${encodeURIComponent(
          targetDeviceId,
        )}/reconcile`,
        {
          method: "POST",
          credentials: "include",
        },
      );

      if (!response.ok) {
        throw new Error(
          `Reconcile failed (${response.status}).`,
        );
      }

      await load();
      setError(null);
    } catch (reconcileError) {
      setError(
        reconcileError instanceof Error
          ? reconcileError.message
          : "Unable to reconcile scoreboard.",
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <section
      data-testid="scoreboard-hardware-operations"
      className="space-y-6"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Hardware stage
            </div>
            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.stage}
            </div>
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-slate-100">
              {summary.readinessPercent}%
            </div>
            <div className="text-xs text-slate-500">
              readiness
            </div>
          </div>
        </div>

        <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
          <div
            className="h-full bg-slate-400 transition-all"
            style={{
              width:
                `${summary.readinessPercent}%`,
            }}
          />
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {[
            [
              "Discovered",
              summary.discovered,
            ],
            [
              "Online",
              summary.online,
            ],
            [
              "Assigned",
              summary.assigned,
            ],
            [
              "Active games",
              summary.activeGames,
            ],
          ].map(
            ([label, value]) => (
              <div
                key={String(label)}
                className="rounded-lg border border-slate-800 bg-slate-950 p-3"
              >
                <div className="text-xs uppercase tracking-wide text-slate-500">
                  {String(label)}
                </div>
                <div className="mt-1 text-2xl font-bold text-slate-100">
                  {String(value)}
                </div>
              </div>
            ),
          )}
        </div>

        {summary.alerts.length > 0 ? (
          <div className="mt-4 grid gap-2">
            {summary.alerts.map(
              (alert) => (
                <div
                  key={alert}
                  className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
                >
                  {alert}
                </div>
              ),
            )}
          </div>
        ) : null}
      </div>

      {error ? (
        <div className="rounded-xl border border-red-900/50 bg-red-950/20 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      ) : null}

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          Game assignment
        </div>

        <div className="mt-4 grid gap-3 md:grid-cols-[1fr_1fr_auto]">
          <input
            value={gameId}
            onChange={(event) =>
              setGameId(
                event.target.value,
              )
            }
            placeholder="Game ID"
            className="rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-sm text-slate-100"
          />

          <input
            value={deviceId}
            onChange={(event) =>
              setDeviceId(
                event.target.value,
              )
            }
            placeholder="Scoreboard device ID"
            className="rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-sm text-slate-100"
          />

          <button
            type="button"
            disabled={busy}
            onClick={() =>
              void assign()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 disabled:opacity-50"
          >
            Assign
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          Current assignments
        </div>

        {assignments.length === 0 ? (
          <div className="mt-3 text-sm text-slate-500">
            No games are assigned to scoreboard devices.
          </div>
        ) : (
          <div className="mt-3 grid gap-2">
            {assignments.map(
              (assignment) => (
                <div
                  key={assignment.gameId}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-800 bg-slate-950 px-3 py-3"
                >
                  <div className="text-sm text-slate-300">
                    <span className="font-mono text-slate-100">
                      {assignment.gameId}
                    </span>
                    {" → "}
                    <span className="font-mono text-slate-100">
                      {assignment.deviceId}
                    </span>
                  </div>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void reconcile(
                        assignment.deviceId,
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200 disabled:opacity-50"
                  >
                    Reconcile Now
                  </button>
                </div>
              ),
            )}
          </div>
        )}
      </div>

      <ScoreboardDeviceOperations />
    </section>
  );
}
EOF

cat > "$OPS_PAGE" <<'EOF'
import {
  ScoreboardHardwareOperationsDashboard,
} from "../../../components/scoreboards/ScoreboardHardwareOperationsDashboard";

export default function ScoreboardOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Hardware Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Scoreboard Hardware Operations
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor physical and simulated scoreboards, manage game assignments,
          review device readiness, and manually reconcile hardware to the latest
          authoritative SportsOS game state.
        </p>
      </div>

      <ScoreboardHardwareOperationsDashboard />
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";
import {
  buildScoreboardHardwareOperationsSummary,
} from "../lib/scoreboard-hardware-operations";

describe("Milestone 10.10 scoreboard hardware operations", () => {
  it("reports no-devices when nothing has connected", () => {
    const summary =
      buildScoreboardHardwareOperationsSummary(
        [],
        [],
      );

    expect(summary.stage).toBe(
      "NO_DEVICES",
    );
    expect(
      summary.alerts.length,
    ).toBeGreaterThan(0);
  });

  it("reports ready when all discovered devices are online", () => {
    const summary =
      buildScoreboardHardwareOperationsSummary(
        [
          {
            deviceId:
              "scoreboard-1",
            state: null,
            telemetry: null,
            lastAcknowledgement:
              null,
            presence: {
              online: true,
              reportedAt:
                new Date(0).toISOString(),
            },
          },
        ],
        [],
      );

    expect(summary.stage).toBe(
      "READY",
    );
    expect(summary.online).toBe(1);
  });

  it("reports active when assignments match online device game state", () => {
    const summary =
      buildScoreboardHardwareOperationsSummary(
        [
          {
            deviceId:
              "scoreboard-1",
            state: {
              gameId: "game-1",
              homeScore: 1,
              awayScore: 0,
              period: 1,
              clock: {
                remainingMs:
                  300000,
                running: true,
              },
              hornActive: false,
              updatedAt:
                new Date(0).toISOString(),
            },
            telemetry: null,
            lastAcknowledgement:
              null,
            presence: {
              online: true,
              reportedAt:
                new Date(0).toISOString(),
            },
          },
        ],
        [
          {
            gameId: "game-1",
            deviceId:
              "scoreboard-1",
            assignedAt:
              new Date(0).toISOString(),
          },
        ],
      );

    expect(summary.stage).toBe(
      "ACTIVE",
    );
    expect(
      summary.activeGames,
    ).toBe(1);
  });

  it("renders assignment and reconcile controls", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/scoreboards/ScoreboardHardwareOperationsDashboard.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="scoreboard-hardware-operations"',
    );
    expect(component).toContain(
      "/scoreboard-devices/assignments",
    );
    expect(component).toContain(
      "/reconcile",
    );
    expect(component).toContain(
      "Reconcile Now",
    );
  });

  it("provides the scoreboard hardware operations page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Scoreboard Hardware Operations",
    );
    expect(page).toContain(
      "ScoreboardHardwareOperationsDashboard",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.10 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - /scoreboards/operations"
echo "  - hardware readiness stage"
echo "  - discovered / online / assigned / active metrics"
echo "  - assignment controls"
echo "  - manual Reconcile Now control"
echo "  - embedded device operations view"
echo "  - hardware alerts / readiness percentage"
echo "  - Milestone 10.10 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green, close Milestone 10 with:"
echo "  npm run build && \\"
echo "  docker compose up -d --build api dashboard scoreboard-simulator && \\"
echo "  npm run test:e2e:docker"
echo
echo "After full green:"
echo "  Milestone 10 complete"
