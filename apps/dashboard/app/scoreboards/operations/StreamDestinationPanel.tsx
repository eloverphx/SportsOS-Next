"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type StreamProtocol =
  | "RTMP"
  | "SRT";

type StreamLatencyMode =
  | "NORMAL"
  | "LOW"
  | "ULTRA_LOW";

type EncoderSessionStatus =
  | "STOPPED"
  | "STARTING"
  | "LIVE"
  | "STOPPING"
  | "ERROR";

type EncoderSession = {
  gameId: string;
  status: EncoderSessionStatus;
  startedAt: string | null;
  stoppedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
};

type EncoderTelemetry = {
  gameId: string;
  health:
    | "IDLE"
    | "STARTING"
    | "HEALTHY"
    | "STALE"
    | "ERROR";
  frame: number | null;
  fps: number | null;
  bitrateKbps: number | null;
  totalSizeBytes: number | null;
  outTimeMs: number | null;
  speed: number | null;
  lastProgressAt: string | null;
  startedAt: string | null;
  lastError: string | null;
};

type EncoderAuditEvent = {
  id: string;
  gameId: string;
  type:
    | "START_REQUESTED"
    | "RUNTIME_STARTED"
    | "RUNTIME_LIVE"
    | "STOP_REQUESTED"
    | "RUNTIME_STOPPED"
    | "RUNTIME_ERROR"
    | "RESTART_SCHEDULED"
    | "RESTARTING"
    | "RESTART_EXHAUSTED";
  timestamp: string;
  detail: string | null;
  attempt: number | null;
};

type EncoderRecoverySnapshot = {
  gameId: string;
  state:
    | "IDLE"
    | "SCHEDULED"
    | "RESTARTING"
    | "EXHAUSTED";
  attempt: number;
  maxAttempts: number;
  nextRetryAt: string | null;
  lastFailureAt: string | null;
};

type StreamingReadinessPreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: Array<{
    id: string;
    passed: boolean;
    message: string;
  }>;
};

type StreamDestinationProfile = {
  gameId: string;
  enabled: boolean;
  protocol: StreamProtocol;
  ingestUrl: string | null;
  streamName: string | null;
  credentialRef: string | null;
  latencyMode: StreamLatencyMode;
  status:
    | "DISABLED"
    | "CONFIGURED"
    | "READY"
    | "LIVE"
    | "ERROR";
  lastError: string | null;
  lastProbeAt: string | null;
  lastProbeLatencyMs: number | null;
  updatedAt: string;
};

function validateDestination(input: {
  enabled: boolean;
  protocol: StreamProtocol;
  ingestUrl: string;
  credentialRef: string;
}): {
  valid: boolean;
  message: string;
} {
  if (!input.enabled) {
    return {
      valid: true,
      message:
        "Streaming is disabled.",
    };
  }

  const ingestUrl =
    input.ingestUrl.trim();

  const credentialRef =
    input.credentialRef.trim();

  if (!ingestUrl) {
    return {
      valid: false,
      message:
        "An ingest URL is required when streaming is enabled.",
    };
  }

  if (
    input.protocol ===
      "RTMP" &&
    !/^rtmps?:\/\//i.test(
      ingestUrl,
    )
  ) {
    return {
      valid: false,
      message:
        "RTMP destinations must begin with rtmp:// or rtmps://.",
    };
  }

  if (
    input.protocol ===
      "SRT" &&
    !/^srt:\/\//i.test(
      ingestUrl,
    )
  ) {
    return {
      valid: false,
      message:
        "SRT destinations must begin with srt://.",
    };
  }

  if (!credentialRef) {
    return {
      valid: false,
      message:
        "A credential reference is required when streaming is enabled.",
    };
  }

  return {
    valid: true,
    message:
      "Destination configuration is valid.",
  };
}

export function StreamDestinationPanel() {
  const [gameId, setGameId] =
    useState("");

  const [profile, setProfile] =
    useState<StreamDestinationProfile | null>(
      null,
    );

  const [enabled, setEnabled] =
    useState(false);

  const [protocol, setProtocol] =
    useState<StreamProtocol>(
      "RTMP",
    );

  const [ingestUrl, setIngestUrl] =
    useState("");

  const [streamName, setStreamName] =
    useState("");

  const [credentialRef, setCredentialRef] =
    useState("");

  const [latencyMode, setLatencyMode] =
    useState<StreamLatencyMode>(
      "NORMAL",
    );

  const [busy, setBusy] =
    useState(false);

  const [error, setError] =
    useState<string | null>(
      null,
    );

  const [
    encoderSession,
    setEncoderSession,
  ] =
    useState<EncoderSession | null>(
      null,
    );

  const [
    encoderTelemetry,
    setEncoderTelemetry,
  ] =
    useState<EncoderTelemetry | null>(
      null,
    );

  const [
    encoderRecovery,
    setEncoderRecovery,
  ] =
    useState<EncoderRecoverySnapshot | null>(
      null,
    );

  const [
    encoderAudit,
    setEncoderAudit,
  ] =
    useState<EncoderAuditEvent[]>(
      [],
    );

  const [
    streamingPreflight,
    setStreamingPreflight,
  ] =
    useState<StreamingReadinessPreflight | null>(
      null,
    );

  const loadEncoderSession =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setEncoderSession(
            null,
          );
          return;
        }

        const response =
          await fetch(
            `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}`,
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

        setEncoderSession(
          json?.data?.session ??
          null,
        );
      },
      [],
    );

  const loadProfile =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setProfile(
            null,
          );
          return;
        }

        const response =
          await fetch(
            `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}`,
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

        const nextProfile =
          json?.data?.profile ??
          null;

        setProfile(
          nextProfile,
        );

        setEnabled(
          nextProfile?.enabled ??
          false,
        );

        setProtocol(
          nextProfile?.protocol ??
          "RTMP",
        );

        setIngestUrl(
          nextProfile?.ingestUrl ??
          "",
        );

        setStreamName(
          nextProfile?.streamName ??
          "",
        );

        setCredentialRef(
          nextProfile?.credentialRef ??
          "",
        );

        setLatencyMode(
          nextProfile?.latencyMode ??
          "NORMAL",
        );
      },
      [],
    );

  useEffect(() => {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          void loadProfile(
            normalized,
          );
          void loadEncoderSession(
            normalized,
          );
        },
        350,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    gameId,
    loadProfile,
    loadEncoderSession,
  ]);

  const validation =
    useMemo(
      () =>
        validateDestination({
          enabled,
          protocol,
          ingestUrl,
          credentialRef,
        }),
      [
        enabled,
        protocol,
        ingestUrl,
        credentialRef,
      ],
    );

  useEffect(() => {
    const normalized = gameId.trim();

    if (
      !normalized ||
      !encoderSession ||
      (
        encoderSession.status !== "STARTING" &&
        encoderSession.status !== "LIVE"
      )
    ) {
      return;
    }

    const timer = window.setInterval(() => {
      void fetch(
        `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/telemetry`,
        { cache: "no-store" },
      )
        .then((response) => response.json())
        .then((json) => {
          setEncoderSession(json?.data?.session ?? null);
          setEncoderTelemetry(json?.data?.telemetry ?? null);
          setEncoderRecovery(json?.data?.recovery ?? null);

          void fetch(
            `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/audit?limit=12`,
            {
              cache:
                "no-store",
            },
          )
            .then(
              (response) =>
                response.json(),
            )
            .then(
              (auditJson) => {
                setEncoderAudit(
                  auditJson?.data?.events ??
                  [],
                );
              },
            )
            .catch(
              () => {
                // Audit history failure must not affect encoder controls.
              },
            );
        })
        .catch(() => {
          // Telemetry polling failure must not affect stream control.
        });
    }, 2000);

    return () => window.clearInterval(timer);
  }, [gameId, encoderSession?.status]);

  async function runStreamingPreflight() {
    const normalized = gameId.trim();
    if (!normalized) return;

    setBusy(true);
    try {
      const response = await fetch(
        `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/preflight`,
        { cache: "no-store" },
      );
      const json = await response.json();
      if (!response.ok) {
        throw new Error(json?.error ?? `Streaming preflight failed (${response.status}).`);
      }
      setStreamingPreflight(json?.data?.preflight ?? null);
      setError(null);
    } catch (preflightError) {
      setError(
        preflightError instanceof Error
          ? preflightError.message
          : "Unable to run streaming preflight.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function startEncoderSession() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/start`,
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
          `Encoder start failed (${response.status}).`,
        );
      }

      setEncoderSession(
        json?.data?.session ??
        null,
      );

      setError(
        null,
      );
    } catch (startError) {
      setError(
        startError instanceof Error
          ? startError.message
          : "Unable to start encoder session.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function stopEncoderSession() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/stop`,
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
          `Encoder stop failed (${response.status}).`,
        );
      }

      setEncoderSession(
        json?.data?.session ??
        null,
      );

      setError(
        null,
      );
    } catch (stopError) {
      setError(
        stopError instanceof Error
          ? stopError.message
          : "Unable to stop encoder session.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function saveProfile() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before saving stream settings.",
      );
      return;
    }

    if (!validation.valid) {
      setError(
        validation.message,
      );
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}`,
          {
            method:
              "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                enabled,
                protocol,
                ingestUrl:
                  ingestUrl.trim() ||
                  null,
                streamName:
                  streamName.trim() ||
                  null,
                credentialRef:
                  credentialRef.trim() ||
                  null,
                latencyMode,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Stream destination save failed (${response.status}).`,
        );
      }

      setProfile(
        json?.data?.profile ??
        null,
      );

      setError(
        null,
      );
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to save stream destination.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function probeDestination() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before probing the stream destination.",
      );
      return;
    }

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}/probe`,
          {
            method: "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Destination probe failed (${response.status}).`,
        );
      }

      setProfile(
        json?.data?.profile ??
        null,
      );

      setError(null);
    } catch (probeError) {
      setError(
        probeError instanceof Error
          ? probeError.message
          : "Unable to probe stream destination.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function resetProfile() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}`,
          {
            method:
              "DELETE",
          },
        );

      if (!response.ok) {
        throw new Error(
          `Stream destination reset failed (${response.status}).`,
        );
      }

      setProfile(
        null,
      );

      setEnabled(
        false,
      );

      setProtocol(
        "RTMP",
      );

      setIngestUrl(
        "",
      );

      setStreamName(
        "",
      );

      setCredentialRef(
        "",
      );

      setLatencyMode(
        "NORMAL",
      );

      setError(
        null,
      );
    } catch (resetError) {
      setError(
        resetError instanceof Error
          ? resetError.message
          : "Unable to reset stream destination.",
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
            Stream Destination
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Configure the encoder destination for a game without exposing raw stream credentials publicly.
          </p>
        </div>

        {profile && (
          <span className="rounded border border-slate-700 px-3 py-1 text-xs">
            {profile.status}
          </span>
        )}
      </div>

      <div className="mt-5">
        <label className="text-xs text-slate-500">
          Game ID
        </label>
        <input
          value={gameId}
          onChange={(event) =>
            setGameId(
              event.target.value,
            )
          }
          placeholder="Game ID"
          className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
        />
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(event) =>
              setEnabled(
                event.target.checked,
              )
            }
          />
          Streaming enabled
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Protocol
          </span>
          <select
            value={protocol}
            onChange={(event) =>
              setProtocol(
                event.target.value as
                  StreamProtocol,
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="RTMP">
              RTMP / RTMPS
            </option>
            <option value="SRT">
              SRT
            </option>
          </select>
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Latency mode
          </span>
          <select
            value={latencyMode}
            onChange={(event) =>
              setLatencyMode(
                event.target.value as
                  StreamLatencyMode,
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="NORMAL">
              Normal
            </option>
            <option value="LOW">
              Low
            </option>
            <option value="ULTRA_LOW">
              Ultra Low
            </option>
          </select>
        </label>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <label className="text-sm md:col-span-2">
          <span className="text-xs text-slate-500">
            Ingest URL
          </span>
          <input
            value={ingestUrl}
            onChange={(event) =>
              setIngestUrl(
                event.target.value,
              )
            }
            placeholder={
              protocol ===
                "RTMP"
                ? "rtmps://..."
                : "srt://..."
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Stream name
          </span>
          <input
            value={streamName}
            onChange={(event) =>
              setStreamName(
                event.target.value,
              )
            }
            placeholder="Game stream"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Credential reference
          </span>
          <input
            value={credentialRef}
            onChange={(event) =>
              setCredentialRef(
                event.target.value,
              )
            }
            placeholder="secret://..."
            autoComplete="off"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
          <span className="mt-1 block text-xs text-slate-600">
            Reference only. Do not paste a raw stream key here.
          </span>
        </label>
      </div>

      <div className="mt-4 rounded-lg border border-slate-800 p-3">
        <div className="text-sm font-semibold">
          Configuration Validation
        </div>
        <p
          className={
            `mt-1 text-xs ${
              validation.valid
                ? "text-slate-500"
                : "text-red-300"
            }`
          }
        >
          {validation.message}
        </p>

        {profile?.lastError && (
          <p className="mt-2 text-xs text-red-300">
            Server status: {profile.lastError}
          </p>
        )}

        {profile?.lastProbeAt && (
          <p className="mt-2 text-xs text-slate-500">
            Last probe: {profile.lastProbeAt}
            {profile.lastProbeLatencyMs != null
              ? ` · ${profile.lastProbeLatencyMs} ms`
              : ""}
          </p>
        )}
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Streaming Readiness
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Validate destination, probe, encoder availability, recovery state, and source configuration before start.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-xs font-medium">
            {streamingPreflight
              ? streamingPreflight.ready
                ? "READY"
                : "BLOCKED"
              : "NOT CHECKED"}
          </span>
        </div>

        <div className="mt-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void runStreamingPreflight()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Run Streaming Preflight
          </button>
        </div>

        {streamingPreflight && (
          <div className="mt-4 space-y-2">
            {streamingPreflight.checks.map(
              (check) => (
                <div
                  key={check.id}
                  className="flex items-start justify-between gap-3 rounded border border-slate-800 p-3"
                >
                  <div>
                    <div className="text-xs font-semibold">
                      {check.id}
                    </div>
                    <div className="mt-1 text-xs text-slate-500">
                      {check.message}
                    </div>
                  </div>

                  <span
                    className={
                      `text-xs font-semibold ${
                        check.passed
                          ? "text-slate-300"
                          : "text-red-300"
                      }`
                    }
                  >
                    {check.passed
                      ? "PASS"
                      : "FAIL"}
                  </span>
                </div>
              ),
            )}
          </div>
        )}
      </div>

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Encoder Session
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Control-plane state only. Milestone 20.4 does not launch FFmpeg or publish media yet.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-xs font-medium">
            {encoderSession?.status ?? "STOPPED"}
          </span>
        </div>

        <div className="mt-3 flex flex-wrap gap-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim() ||
              profile?.status !==
                "READY" ||
              encoderSession?.status ===
                "STARTING" ||
              encoderSession?.status ===
                "LIVE"
            }
            onClick={() =>
              void startEncoderSession()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Arm Encoder Start
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim() ||
              !encoderSession ||
              encoderSession.status ===
                "STOPPED"
            }
            onClick={() =>
              void stopEncoderSession()
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Stop Encoder Session
          </button>
        </div>

        {encoderSession?.lastError && (
          <p className="mt-3 text-xs text-red-300">
            Encoder status: {encoderSession.lastError}
          </p>
        )}

        <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">Publish Health</div>
            <div className="mt-1 font-semibold">{encoderTelemetry?.health ?? "IDLE"}</div>
          </div>
          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">FPS</div>
            <div className="mt-1 font-semibold">{encoderTelemetry?.fps ?? "--"}</div>
          </div>
          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">Bitrate</div>
            <div className="mt-1 font-semibold">{encoderTelemetry?.bitrateKbps != null ? `${encoderTelemetry.bitrateKbps} kbps` : "--"}</div>
          </div>
          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">Speed</div>
            <div className="mt-1 font-semibold">{encoderTelemetry?.speed != null ? `${encoderTelemetry.speed}x` : "--"}</div>
          </div>
        </div>

        {encoderTelemetry?.lastProgressAt && (
          <p className="mt-3 text-xs text-slate-500">
            Last encoder progress: {encoderTelemetry.lastProgressAt}
          </p>
        )}

        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Recovery State
            </div>
            <div className="mt-1 font-semibold">
              {encoderRecovery?.state ?? "IDLE"}
            </div>
          </div>

          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Restart Attempts
            </div>
            <div className="mt-1 font-semibold">
              {encoderRecovery
                ? `${encoderRecovery.attempt}/${encoderRecovery.maxAttempts}`
                : "0/0"}
            </div>
          </div>

          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Next Retry
            </div>
            <div className="mt-1 text-sm">
              {encoderRecovery?.nextRetryAt ?? "--"}
            </div>
          </div>
        </div>
        <div className="mt-5">
          <div className="text-sm font-semibold">
            Encoder Runtime History
          </div>

          <div className="mt-2 space-y-2">
            {encoderAudit.length === 0 ? (
              <div className="rounded border border-slate-800 p-3 text-xs text-slate-500">
                No encoder runtime events recorded.
              </div>
            ) : (
              encoderAudit.map(
                (event) => (
                  <div
                    key={event.id}
                    className="rounded border border-slate-800 p-3"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-xs font-semibold">
                        {event.type}
                      </span>
                      <span className="text-xs text-slate-500">
                        {event.timestamp}
                      </span>
                    </div>

                    {event.detail && (
                      <div className="mt-1 text-xs text-slate-400">
                        {event.detail}
                      </div>
                    )}

                    {event.attempt != null && (
                      <div className="mt-1 text-xs text-slate-500">
                        Attempt {event.attempt}
                      </div>
                    )}
                  </div>
                ),
              )
            )}
          </div>
        </div>

      </div>

      <div className="mt-4 flex flex-wrap gap-3">
        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim() ||
            !validation.valid
          }
          onClick={() =>
            void saveProfile()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Save Stream Destination
        </button>

        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim() ||
            !enabled ||
            !validation.valid
          }
          onClick={() =>
            void probeDestination()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Probe Destination
        </button>

        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim()
          }
          onClick={() =>
            void resetProfile()
          }
          className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
        >
          Reset Stream Destination
        </button>
      </div>
    </section>
  );
}
