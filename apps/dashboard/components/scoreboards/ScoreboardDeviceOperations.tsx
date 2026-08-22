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
