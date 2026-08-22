#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.5-device-operations-ui"
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

PAGE="apps/dashboard/app/scoreboards/page.tsx"
CLIENT="apps/dashboard/components/scoreboards/ScoreboardDeviceOperations.tsx"
LIB="apps/dashboard/lib/scoreboard-devices.ts"
TEST="apps/dashboard/test/scoreboard-device-operations-10.5.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$CLIENT")" \
  "$BACKUP_DIR/$(dirname "$LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$PAGE")" \
  "$(dirname "$CLIENT")"

for file in "$PAGE" "$CLIENT" "$LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$LIB" <<'EOF'
export type ScoreboardDeviceRuntime = {
  deviceId: string;
  state: {
    gameId: string | null;
    homeScore: number;
    awayScore: number;
    period: number | null;
    clock: {
      remainingMs: number;
      running: boolean;
    };
    hornActive: boolean;
    updatedAt: string;
  } | null;
  presence: {
    online: boolean;
    reportedAt: string;
  } | null;
  telemetry: {
    firmwareVersion: string | null;
    ipAddress: string | null;
    wifiRssi: number | null;
    uptimeSeconds: number;
    freeHeapBytes: number | null;
    reportedAt: string;
  } | null;
  lastAcknowledgement: {
    commandId: string;
    status: "ACCEPTED" | "REJECTED" | "APPLIED";
    message: string | null;
    acknowledgedAt: string;
  } | null;
};

export type ScoreboardDevicesResponse = {
  success: boolean;
  data?: {
    devices: ScoreboardDeviceRuntime[];
  };
};

export function formatScoreboardClock(
  remainingMs: number,
): string {
  const totalSeconds = Math.max(
    0,
    Math.floor(remainingMs / 1000),
  );
  const minutes = Math.floor(
    totalSeconds / 60,
  );
  const seconds = totalSeconds % 60;

  return `${minutes}:${seconds
    .toString()
    .padStart(2, "0")}`;
}

export function scoreboardDeviceHealth(
  device: ScoreboardDeviceRuntime,
): "ONLINE" | "OFFLINE" | "UNKNOWN" {
  if (!device.presence) {
    return "UNKNOWN";
  }

  return device.presence.online
    ? "ONLINE"
    : "OFFLINE";
}
EOF

cat > "$CLIENT" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  formatScoreboardClock,
  scoreboardDeviceHealth,
  type ScoreboardDeviceRuntime,
  type ScoreboardDevicesResponse,
} from "../../lib/scoreboard-devices";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ??
  "";

async function fetchDevices(): Promise<
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
      `Failed to load scoreboard devices (${response.status}).`,
    );
  }

  const payload =
    (await response.json()) as ScoreboardDevicesResponse;

  return payload.data?.devices ?? [];
}

async function sendCommand(
  deviceId: string,
  command: Record<string, unknown>,
): Promise<void> {
  const response = await fetch(
    `${API_BASE_URL}/scoreboard-devices/${encodeURIComponent(
      deviceId,
    )}/commands`,
    {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(command),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      text ||
        `Command failed (${response.status}).`,
    );
  }
}

export function ScoreboardDeviceOperations() {
  const [devices, setDevices] = useState<
    ScoreboardDeviceRuntime[]
  >([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] =
    useState<string | null>(null);
  const [busyDeviceId, setBusyDeviceId] =
    useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const next = await fetchDevices();
      setDevices(next);
      setError(null);
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : "Unable to load scoreboard devices.",
      );
    } finally {
      setLoading(false);
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

  const onlineCount = useMemo(
    () =>
      devices.filter(
        (device) =>
          scoreboardDeviceHealth(device) ===
          "ONLINE",
      ).length,
    [devices],
  );

  const runCommand = async (
    deviceId: string,
    command: Record<string, unknown>,
  ) => {
    setBusyDeviceId(deviceId);

    try {
      await sendCommand(
        deviceId,
        command,
      );

      window.setTimeout(
        () => void load(),
        300,
      );
    } catch (commandError) {
      setError(
        commandError instanceof Error
          ? commandError.message
          : "Unable to send scoreboard command.",
      );
    } finally {
      setBusyDeviceId(null);
    }
  };

  return (
    <section
      data-testid="scoreboard-device-operations"
      className="space-y-6"
    >
      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Discovered devices
          </div>
          <div className="mt-2 text-3xl font-bold text-slate-100">
            {devices.length}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Online
          </div>
          <div className="mt-2 text-3xl font-bold text-slate-100">
            {onlineCount}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Polling
          </div>
          <div className="mt-2 text-sm font-semibold text-slate-300">
            Every 3 seconds
          </div>
        </div>
      </div>

      {error ? (
        <div className="rounded-xl border border-red-900/50 bg-red-950/20 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      ) : null}

      {loading ? (
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-6 text-sm text-slate-400">
          Loading scoreboard devices…
        </div>
      ) : devices.length === 0 ? (
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-6 text-sm text-slate-400">
          No scoreboard devices have reported through MQTT yet.
        </div>
      ) : (
        <div className="grid gap-4 xl:grid-cols-2">
          {devices.map((device) => {
            const health =
              scoreboardDeviceHealth(
                device,
              );

            const busy =
              busyDeviceId ===
              device.deviceId;

            return (
              <article
                key={device.deviceId}
                className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
              >
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="text-xs uppercase tracking-wide text-slate-500">
                      Device
                    </div>
                    <div className="mt-1 font-mono text-lg font-bold text-slate-100">
                      {device.deviceId}
                    </div>
                  </div>

                  <div className="rounded-full border border-slate-700 px-3 py-1 text-xs font-semibold text-slate-300">
                    {health}
                  </div>
                </div>

                <div className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
                  <Metric
                    label="Home"
                    value={
                      device.state?.homeScore ??
                      "—"
                    }
                  />
                  <Metric
                    label="Away"
                    value={
                      device.state?.awayScore ??
                      "—"
                    }
                  />
                  <Metric
                    label="Period"
                    value={
                      device.state?.period ??
                      "—"
                    }
                  />
                  <Metric
                    label="Clock"
                    value={
                      device.state
                        ? formatScoreboardClock(
                            device.state.clock
                              .remainingMs,
                          )
                        : "—"
                    }
                  />
                </div>

                <div className="mt-4 grid gap-2 text-xs text-slate-400 sm:grid-cols-2">
                  <div>
                    Game:{" "}
                    <span className="text-slate-200">
                      {device.state?.gameId ??
                        "Unassigned"}
                    </span>
                  </div>
                  <div>
                    Clock:{" "}
                    <span className="text-slate-200">
                      {device.state?.clock.running
                        ? "RUNNING"
                        : "PAUSED"}
                    </span>
                  </div>
                  <div>
                    Firmware:{" "}
                    <span className="text-slate-200">
                      {device.telemetry
                        ?.firmwareVersion ??
                        "Unknown"}
                    </span>
                  </div>
                  <div>
                    RSSI:{" "}
                    <span className="text-slate-200">
                      {device.telemetry
                        ?.wifiRssi ??
                        "—"}
                    </span>
                  </div>
                  <div>
                    IP:{" "}
                    <span className="text-slate-200">
                      {device.telemetry
                        ?.ipAddress ??
                        "—"}
                    </span>
                  </div>
                  <div>
                    Last ACK:{" "}
                    <span className="text-slate-200">
                      {device
                        .lastAcknowledgement
                        ?.status ??
                        "—"}
                    </span>
                  </div>
                </div>

                <div className="mt-5 flex flex-wrap gap-2">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void runCommand(
                        device.deviceId,
                        {
                          protocolVersion: 1,
                          commandId:
                            `horn-on-${Date.now()}`,
                          type: "HORN",
                          active: true,
                        },
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200 disabled:opacity-50"
                  >
                    Horn On
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void runCommand(
                        device.deviceId,
                        {
                          protocolVersion: 1,
                          commandId:
                            `horn-off-${Date.now()}`,
                          type: "HORN",
                          active: false,
                        },
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200 disabled:opacity-50"
                  >
                    Horn Off
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void runCommand(
                        device.deviceId,
                        {
                          protocolVersion: 1,
                          commandId:
                            `clock-pause-${Date.now()}`,
                          type: "SET_CLOCK",
                          remainingMs:
                            device.state?.clock
                              .remainingMs ??
                            0,
                          running: false,
                        },
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200 disabled:opacity-50"
                  >
                    Pause Clock
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}

function Metric(props: {
  label: string;
  value: string | number;
}) {
  return (
    <div className="rounded-lg border border-slate-800 bg-slate-950 p-3">
      <div className="text-xs uppercase tracking-wide text-slate-500">
        {props.label}
      </div>
      <div className="mt-1 text-xl font-bold text-slate-100">
        {props.value}
      </div>
    </div>
  );
}
EOF

cat > "$PAGE" <<'EOF'
import {
  ScoreboardDeviceOperations,
} from "../../components/scoreboards/ScoreboardDeviceOperations";

export default function ScoreboardsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Hardware
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Scoreboard Devices
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor physical and simulated scoreboard devices connected through
          MQTT, review telemetry and state, and send safe device test commands.
        </p>
      </div>

      <ScoreboardDeviceOperations />
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  formatScoreboardClock,
  scoreboardDeviceHealth,
} from "../lib/scoreboard-devices";

describe("Milestone 10.5 scoreboard device operations UI", () => {
  it("formats scoreboard time", () => {
    expect(
      formatScoreboardClock(125000),
    ).toBe("2:05");
  });

  it("derives device online state", () => {
    expect(
      scoreboardDeviceHealth({
        deviceId: "scoreboard-1",
        state: null,
        telemetry: null,
        lastAcknowledgement: null,
        presence: {
          online: true,
          reportedAt:
            "2026-08-17T21:00:00.000Z",
        },
      }),
    ).toBe("ONLINE");
  });

  it("renders the device operations component", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/scoreboards/ScoreboardDeviceOperations.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="scoreboard-device-operations"',
    );
    expect(component).toContain(
      "/scoreboard-devices",
    );
    expect(component).toContain(
      "/commands",
    );
    expect(component).toContain(
      "Horn On",
    );
    expect(component).toContain(
      "Pause Clock",
    );
  });

  it("provides the scoreboard devices page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/scoreboards/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Scoreboard Devices",
    );
    expect(page).toContain(
      "ScoreboardDeviceOperations",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.5 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - /scoreboards device operations page"
echo "  - device discovery / online status"
echo "  - score / period / clock display"
echo "  - firmware / IP / RSSI telemetry"
echo "  - last acknowledgement visibility"
echo "  - Horn On / Horn Off / Pause Clock test controls"
echo "  - 3-second device refresh"
echo "  - Milestone 10.5 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build"
echo "  docker compose up -d --build dashboard"
echo
echo "Next after green:"
echo "  Milestone 10.6 - Game-to-Scoreboard Synchronization"
