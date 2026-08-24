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
  scheduledStartAt: string | null;
  startWindowEarlyMinutes: number;
  startWindowLateMinutes: number;
  autoArmEnabled: boolean;
  autoArmLeadMinutes: number;
  healthHoldSeconds: number;
  healthySinceAt: string | null;
  degradedAt: string | null;
  degradationReason: string | null;
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

type GoLiveAuditEvent = {
  id: string;
  gameId: string;
  type: string;
  timestamp: string;
  detail: string | null;
  operator: string | null;
};

type GameDayGoLivePreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: Array<{
    id: string;
    passed: boolean;
    message: string;
  }>;
};

type GoLiveSession = {
  gameId: string;
  status:
    | "IDLE"
    | "ARMED"
    | "STARTING"
    | "LIVE"
    | "DEGRADED"
    | "STOPPING"
    | "COMPLETE"
    | "EMERGENCY_STOPPED"
    | "ERROR";
  armedAt: string | null;
  startedAt: string | null;
  liveAt: string | null;
  stoppedAt: string | null;
  completedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
  degradedAt: string | null;
  degradationReason: string | null;
  incidentAcknowledgedAt: string | null;
  incidentAcknowledgedBy: string | null;
emergencyStoppedAt: string | null;
  emergencyStopReason: string | null;
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

  const [
    goLiveSession,
    setGoLiveSession,
  ] =
    useState<GoLiveSession | null>(
      null,
    );

  const [
    gameDayGoLivePreflight,
    setGameDayGoLivePreflight,
  ] =
    useState<GameDayGoLivePreflight | null>(
      null,
    );

  const [
    goLiveAudit,
    setGoLiveAudit,
  ] =
    useState<GoLiveAuditEvent[]>(
      [],
    );



  const [
    scheduledStartAt,
    setScheduledStartAt,
  ] =
    useState("");

  const [
    startWindowEarlyMinutes,
    setStartWindowEarlyMinutes,
  ] =
    useState(15);

  const [
    startWindowLateMinutes,
    setStartWindowLateMinutes,
  ] =
    useState(15);

  const [
    goLiveStartWindow,
    setGoLiveStartWindow,
  ] =
    useState<{
      scheduled: boolean;
      withinWindow: boolean;
      tooEarly: boolean;
      tooLate: boolean;
      opensAt: string | null;
      closesAt: string | null;
    } | null>(
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

  const [autoArmEnabled, setAutoArmEnabled] = useState(false);
  const [autoArmLeadMinutes, setAutoArmLeadMinutes] = useState(30);
  const [goLiveCountdown, setGoLiveCountdown] = useState<{ scheduled:boolean; scheduledStartAt:string|null; secondsUntilStart:number|null; autoArmAt:string|null; autoArmDue:boolean } | null>(null);

  const [
    healthHoldSeconds,
    setHealthHoldSeconds,
  ] =
    useState(10);

  const [
    goLiveHealthHold,
    setGoLiveHealthHold,
  ] =
    useState<{
      readyToConfirm: boolean;
      healthySinceAt: string | null;
      holdSeconds: number;
      healthyForSeconds: number;
      remainingSeconds: number;
    } | null>(
      null,
    );

  const [
    incidentOperator,
    setIncidentOperator,
  ] =
    useState("");

  const [
    emergencyStopReason,
    setEmergencyStopReason,
  ] =
    useState("");

  async function emergencyStopGoLive() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/emergency-stop`,
          {
            method:
              "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                reason:
                  emergencyStopReason.trim() ||
                  null,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          "Emergency stop failed.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setEncoderSession(
        json?.data?.runtime?.session ??
        null,
      );

      setEncoderTelemetry(
        json?.data?.runtime?.telemetry ??
        null,
      );

      setError(null);
    } catch (stopError) {
      setError(
        stopError instanceof Error
          ? stopError.message
          : "Emergency stop failed.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function acknowledgeIncident() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/incident/acknowledge`,
          {
            method:
              "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                operator:
                  incidentOperator.trim() ||
                  null,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          "Unable to acknowledge incident.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setError(null);
    } catch (ackError) {
      setError(
        ackError instanceof Error
          ? ackError.message
          : "Unable to acknowledge incident.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function retryIncidentWatchdog() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/incident/retry-watchdog`,
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
          "Unable to retry watchdog.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      await runLiveWatchdog();

      setError(null);
    } catch (retryError) {
      setError(
        retryError instanceof Error
          ? retryError.message
          : "Unable to retry incident watchdog.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function runLiveWatchdog() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    try {
      const response =
        await fetch(
          `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/watchdog`,
          {
            method:
              "POST",
          },
        );

      if (!response.ok) return;

      const json =
        await response.json();

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setEncoderSession(
        json?.data?.runtime?.session ??
        null,
      );

      setEncoderTelemetry(
        json?.data?.runtime?.telemetry ??
        null,
      );
    } catch {
      // Watchdog polling failure must not interrupt operator controls.
    }
  }

  useEffect(() => {
    if (
      goLiveSession?.status !== "LIVE" &&
      goLiveSession?.status !== "DEGRADED"
    ) {
      return;
    }

    const timer =
      window.setInterval(
        () => {
          void runLiveWatchdog();
        },
        3000,
      );

    return () => {
      window.clearInterval(
        timer,
      );
    };
  }, [
    gameId,
    goLiveSession?.status,
  ]);

  async function saveHealthHold() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/health-hold`,
          {
            method:
              "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                seconds:
                  healthHoldSeconds,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          "Unable to save health hold.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setError(null);
    } catch (holdError) {
      setError(
        holdError instanceof Error
          ? holdError.message
          : "Unable to save health hold.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function refreshHealthHold() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    const response =
      await fetch(
        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/health-hold`,
        {
          cache:
            "no-store",
        },
      );

    if (!response.ok) return;

    const json =
      await response.json();

    setGoLiveSession(
      json?.data?.session ??
      null,
    );

    setGoLiveHealthHold(
      json?.data?.healthHold ??
      null,
    );
  }

  async function saveAutoArmSettings() {
    const normalized = gameId.trim(); if (!normalized) return;
    setBusy(true);
    try {
      const response = await fetch(`${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/auto-arm`, { method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({enabled:autoArmEnabled,leadMinutes:autoArmLeadMinutes}) });
      const json = await response.json(); if (!response.ok) throw new Error(json?.error ?? "Auto-arm save failed.");
      setGoLiveSession(json?.data?.session ?? null); setGoLiveCountdown(json?.data?.countdown ?? null); setError(null);
    } catch (e) { setError(e instanceof Error ? e.message : "Unable to save auto-arm settings."); } finally { setBusy(false); }
  }

  async function evaluateAutoArm() {
    const normalized=gameId.trim(); if(!normalized) return;
    const response=await fetch(`${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/auto-arm/evaluate`,{method:"POST"});
    const json=await response.json(); setGoLiveSession(json?.data?.session ?? null); setGoLiveCountdown(json?.data?.countdown ?? null);
    if(!response.ok) setError(json?.error ?? "Auto-arm evaluation failed.");
  }

  async function saveGoLiveSchedule() {
    const normalized = gameId.trim();
    if (!normalized) return;
    setBusy(true);
    try {
      const response = await fetch(
        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/schedule`,
        {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            scheduledStartAt: scheduledStartAt ? new Date(scheduledStartAt).toISOString() : null,
            startWindowEarlyMinutes,
            startWindowLateMinutes,
          }),
        },
      );
      const json = await response.json();
      if (!response.ok) throw new Error(json?.error ?? `Schedule save failed (${response.status}).`);
      setGoLiveSession(json?.data?.session ?? null);
      setGoLiveStartWindow(json?.data?.startWindow ?? null);
      setError(null);
    } catch (scheduleError) {
      setError(scheduleError instanceof Error ? scheduleError.message : "Unable to save go-live schedule.");
    } finally {
      setBusy(false);
    }
  }

  async function refreshGoLiveStartWindow() {
    const normalized = gameId.trim();
    if (!normalized) return;
    const response = await fetch(
      `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/start-window`,
      { cache: "no-store" },
    );
    if (!response.ok) return;
    const json = await response.json();
    setGoLiveSession(json?.data?.session ?? null);
    setGoLiveStartWindow(json?.data?.startWindow ?? null);
  }

  async function runGameDayGoLivePreflight() {
    const normalized = gameId.trim();
    if (!normalized) return;
    setBusy(true);
    try {
      const response = await fetch(
        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/game-day-preflight`,
        { cache: "no-store" },
      );
      const json = await response.json();
      if (!response.ok) throw new Error(json?.error ?? "Unable to run game-day go-live preflight.");
      setGameDayGoLivePreflight(json?.data?.preflight ?? null);
      setError(null);
    } catch (preflightError) {
      setError(preflightError instanceof Error ? preflightError.message : "Unable to run game-day go-live preflight.");
    } finally {
      setBusy(false);
    }
  }

  async function refreshGoLiveAudit() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    try {
      const response =
        await fetch(
          `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/audit?limit=25`,
          {
            cache:
              "no-store",
          },
        );

      if (!response.ok) return;

      const json =
        await response.json();

      setGoLiveAudit(
        json?.data?.events ??
        [],
      );
    } catch {
      // Audit history failure must not affect go-live controls.
    }
  }

  async function loadGoLiveSession() {
    const normalized = gameId.trim();
    if (!normalized) return;
    const response = await fetch(
      `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}`,
      { cache: "no-store" },
    );
    if (!response.ok) return;
    const json = await response.json();
    setGoLiveSession(json?.data?.session ?? null);
  }

  async function goLiveAction(action: "arm" | "start" | "confirm-live" | "stop" | "reset") {
    const normalized = gameId.trim();
    if (!normalized) return;
    setBusy(true);
    try {
      const response = await fetch(
        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/${action}`,
        { method: "POST" },
      );
      const json = await response.json();
      if (!response.ok) {
        throw new Error(json?.error ?? `Go-live action failed (${response.status}).`);
      }
      setGoLiveSession(json?.data?.session ?? null);
      setError(null);
    } catch (actionError) {
      setError(
        actionError instanceof Error
          ? actionError.message
          : "Unable to complete go-live action.",
      );
    } finally {
      setBusy(false);
    }
  }

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
              Production Go-Live
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Orchestrates readiness and encoder state without duplicating game-state authority.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-xs font-medium">
            {goLiveSession?.status ?? "IDLE"}
          </span>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-3">
          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Scheduled Start
            </span>
            <input
              type="datetime-local"
              value={scheduledStartAt}
              onChange={(event) =>
                setScheduledStartAt(
                  event.target.value,
                )
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Early Window (minutes)
            </span>
            <input
              type="number"
              min={0}
              max={120}
              value={startWindowEarlyMinutes}
              onChange={(event) =>
                setStartWindowEarlyMinutes(
                  Number(event.target.value) || 0,
                )
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Late Window (minutes)
            </span>
            <input
              type="number"
              min={0}
              max={120}
              value={startWindowLateMinutes}
              onChange={(event) =>
                setStartWindowLateMinutes(
                  Number(event.target.value) || 0,
                )
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        </div>

        <div className="mt-3 flex flex-wrap gap-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void saveGoLiveSchedule()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Save Go-Live Schedule
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void refreshGoLiveStartWindow()
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Refresh Start Window
          </button>
        </div>

        {goLiveStartWindow && (
          <div className="mt-3 rounded border border-slate-800 p-3 text-xs">
            <div className="font-semibold">
              Start Window: {goLiveStartWindow.withinWindow ? "OPEN" : goLiveStartWindow.tooEarly ? "TOO EARLY" : goLiveStartWindow.tooLate ? "EXPIRED" : "OPEN"}
            </div>
            {goLiveStartWindow.opensAt && (
              <div className="mt-1 text-slate-500">
                Opens: {goLiveStartWindow.opensAt}
              </div>
            )}
            {goLiveStartWindow.closesAt && (
              <div className="mt-1 text-slate-500">
                Closes: {goLiveStartWindow.closesAt}
              </div>
            )}
          </div>
        )}

        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">Auto-Arm Countdown</div>
          <div className="mt-3 flex flex-wrap items-end gap-3">
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={autoArmEnabled} onChange={(e) => setAutoArmEnabled(e.target.checked)} />Enable scheduled auto-arm</label>
            <label className="text-sm"><span className="text-xs text-slate-500">Auto-Arm Lead (minutes)</span><input type="number" min={0} max={240} value={autoArmLeadMinutes} onChange={(e) => setAutoArmLeadMinutes(Number(e.target.value)||0)} className="mt-1 block rounded-lg border border-slate-700 bg-slate-950 px-3 py-2" /></label>
            <button type="button" disabled={busy || !gameId.trim()} onClick={() => void saveAutoArmSettings()} className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50">Save Auto-Arm</button>
            <button type="button" disabled={busy || !gameId.trim()} onClick={() => void evaluateAutoArm()} className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50">Evaluate Auto-Arm</button>
          </div>
          {goLiveCountdown && <div className="mt-3 text-xs text-slate-400">Countdown: {goLiveCountdown.secondsUntilStart == null ? "Not scheduled" : `${goLiveCountdown.secondsUntilStart}s`} · Auto-arm due: {goLiveCountdown.autoArmDue ? "YES" : "NO"}</div>}
        </div>

        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">
            Go-Live Health Hold
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Requires continuous healthy publish telemetry before the broadcast can be confirmed live.
          </p>

          <div className="mt-3 flex flex-wrap items-end gap-3">
            <label className="text-sm">
              <span className="text-xs text-slate-500">
                Confirmation Hold (seconds)
              </span>
              <input
                type="number"
                min={0}
                max={120}
                value={healthHoldSeconds}
                onChange={(event) =>
                  setHealthHoldSeconds(
                    Number(event.target.value) || 0,
                  )
                }
                className="mt-1 block rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
              />
            </label>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void saveHealthHold()
              }
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
            >
              Save Health Hold
            </button>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void refreshHealthHold()
              }
              className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
            >
              Refresh Health Hold
            </button>
          </div>

          {goLiveHealthHold && (
            <div className="mt-3 text-xs text-slate-400">
              <div>
                Confirmation: {goLiveHealthHold.readyToConfirm ? "READY" : "HOLDING"}
              </div>
              <div className="mt-1">
                Healthy for: {goLiveHealthHold.healthyForSeconds}s / {goLiveHealthHold.holdSeconds}s
              </div>
              <div className="mt-1">
                Remaining: {goLiveHealthHold.remainingSeconds}s
              </div>
            </div>
          )}
        </div>

        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">
            Live Broadcast Watchdog
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Checks encoder state and publish health every 3 seconds while the production session is live.
          </p>

          <div className="mt-3 flex flex-wrap items-center gap-3">
            <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
              {goLiveSession?.status === "DEGRADED"
                ? "DEGRADED"
                : goLiveSession?.status === "LIVE"
                  ? "HEALTHY"
                  : "INACTIVE"}
            </span>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void runLiveWatchdog()
              }
              className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
            >
              Run Watchdog Check
            </button>
          </div>

          {goLiveSession?.degradationReason && (
            <div className="mt-3 rounded border border-red-900/50 bg-red-950/20 p-3 text-xs text-red-300">
              {goLiveSession.degradationReason}
            </div>
          )}
        </div>

        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">
            Live Incident Controls
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Acknowledge a degraded broadcast and explicitly retry health evaluation after operator action.
          </p>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <label className="text-sm">
              <span className="text-xs text-slate-500">
                Operator / Note
              </span>
              <input
                value={incidentOperator}
                onChange={(event) =>
                  setIncidentOperator(
                    event.target.value,
                  )
                }
                placeholder="Operator name or console"
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
              />
            </label>

            <div className="flex flex-wrap items-end gap-3">
              <button
                type="button"
                disabled={
                  busy ||
                  goLiveSession?.status !==
                    "DEGRADED"
                }
                onClick={() =>
                  void acknowledgeIncident()
                }
                className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
              >
                Acknowledge Incident
              </button>

              <button
                type="button"
                disabled={
                  busy ||
                  goLiveSession?.status !==
                    "DEGRADED"
                }
                onClick={() =>
                  void retryIncidentWatchdog()
                }
                className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
              >
                Retry Health Check
              </button>
            </div>
          </div>

          {goLiveSession?.incidentAcknowledgedAt && (
            <div className="mt-3 text-xs text-slate-400">
              Acknowledged: {goLiveSession.incidentAcknowledgedAt}
              {goLiveSession.incidentAcknowledgedBy
                ? ` · ${goLiveSession.incidentAcknowledgedBy}`
                : ""}
            </div>
          )}
        </div>

        <div className="mt-4 rounded border border-red-900/50 bg-red-950/10 p-3">
          <div className="text-sm font-semibold text-red-300">
            Emergency Broadcast Stop
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Immediately stops the encoder runtime and suppresses automatic recovery. Reset is required before another start.
          </p>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <label className="text-sm">
              <span className="text-xs text-slate-500">
                Emergency Stop Reason
              </span>
              <input
                value={emergencyStopReason}
                onChange={(event) =>
                  setEmergencyStopReason(
                    event.target.value,
                  )
                }
                placeholder="Reason for emergency stop"
                className="mt-1 w-full rounded-lg border border-red-900/50 bg-slate-950 px-3 py-2"
              />
            </label>

            <div className="flex items-end">
              <button
                type="button"
                disabled={
                  busy ||
                  !gameId.trim() ||
                  goLiveSession?.status ===
                    "IDLE" ||
                  goLiveSession?.status ===
                    "COMPLETE" ||
                  goLiveSession?.status ===
                    "EMERGENCY_STOPPED"
                }
                onClick={() =>
                  void emergencyStopGoLive()
                }
                className="rounded-lg border border-red-800 px-4 py-2 text-sm font-semibold text-red-300 disabled:opacity-50"
              >
                Emergency Stop Broadcast
              </button>
            </div>
          </div>

          {goLiveSession?.status === "EMERGENCY_STOPPED" && (
            <div className="mt-3 rounded border border-red-900/50 p-3 text-xs text-red-300">
              Emergency stopped
              {goLiveSession.emergencyStopReason
                ? `: ${goLiveSession.emergencyStopReason}`
                : ""}
            </div>
          )}
        </div>

        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="text-sm font-semibold">
              Go-Live Session History
            </div>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void refreshGoLiveAudit()
              }
              className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
            >
              Refresh Go-Live History
            </button>
          </div>

          <div className="mt-3 space-y-2">
            {goLiveAudit.length === 0 ? (
              <div className="rounded border border-slate-800 p-3 text-xs text-slate-500">
                No go-live events recorded.
              </div>
            ) : (
              goLiveAudit.map(
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

                    {event.operator && (
                      <div className="mt-1 text-xs text-slate-500">
                        Operator: {event.operator}
                      </div>
                    )}
                  </div>
                ),
              )
            )}
          </div>
        </div>

        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="text-sm font-semibold">
                Game-Day Go-Live Preflight
              </div>
              <p className="mt-1 text-xs text-slate-500">
                Final production gate combining schedule, readiness, encoder, recovery, incident, and emergency-stop status.
              </p>
            </div>

            <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
              {gameDayGoLivePreflight
                ? gameDayGoLivePreflight.ready
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
                void runGameDayGoLivePreflight()
              }
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
            >
              Run Final Go-Live Preflight
            </button>
          </div>

          {gameDayGoLivePreflight && (
            <div className="mt-4 space-y-2">
              {gameDayGoLivePreflight.checks.map(
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

                    <span className={`text-xs font-semibold ${check.passed ? "text-slate-300" : "text-red-300"}`}>
                      {check.passed ? "PASS" : "FAIL"}
                    </span>
                  </div>
                ),
              )}
            </div>
          )}
        </div>

        <div className="mt-4 flex flex-wrap gap-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void loadGoLiveSession()
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Refresh Go-Live State
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !streamingPreflight?.ready ||
              (
                goLiveSession?.status != null &&
                goLiveSession.status !== "IDLE" &&
                goLiveSession.status !== "COMPLETE" &&
                goLiveSession.status !== "ERROR"
              )
            }
            onClick={() =>
              void goLiveAction("arm")
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Arm Go-Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              goLiveSession?.status !== "ARMED"
            }
            onClick={() =>
              void goLiveAction("start")
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Start Go-Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              goLiveSession?.status !== "STARTING"
            }
            onClick={() =>
              void goLiveAction("confirm-live")
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Confirm Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              (
                goLiveSession?.status !== "STARTING" &&
                goLiveSession?.status !== "LIVE"
              )
            }
            onClick={() =>
              void goLiveAction("stop")
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Stop Go-Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !goLiveSession ||
              (
                goLiveSession.status !== "COMPLETE" &&
                goLiveSession.status !== "ERROR"
              )
            }
            onClick={() =>
              void goLiveAction("reset")
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Reset Go-Live
          </button>
        </div>

        {goLiveSession?.lastError && (
          <p className="mt-3 text-xs text-red-300">
            Go-live status: {goLiveSession.lastError}
          </p>
        )}
      </div>

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
