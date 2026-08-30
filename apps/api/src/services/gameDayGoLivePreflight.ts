import {
  encoderRuntimeSnapshot,
} from "./encoderRuntime.js";

import {
  evaluateGoLiveCountdown,
  evaluateGoLiveStartWindow,
  getGoLiveSession,
} from "./goLiveSession.js";

import {
  evaluateStreamingReadiness,
} from "./streamingReadinessPreflight.js";

export type GameDayGoLiveCheck = {
  id:
    | "STREAMING_PREFLIGHT"
    | "START_WINDOW"
    | "GO_LIVE_STATE"
    | "EMERGENCY_STOP"
    | "DEGRADED_INCIDENT"
    | "RECOVERY_EXHAUSTION"
    | "ENCODER_AVAILABILITY"
    | "SCHEDULE_COUNTDOWN";
  passed: boolean;
  message: string;
};

export type GameDayGoLivePreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: GameDayGoLiveCheck[];
};

export function evaluateGameDayGoLivePreflight(
  gameId: string,
): GameDayGoLivePreflight {
  const session =
    getGoLiveSession(
      gameId,
    );

  const streaming =
    evaluateStreamingReadiness(
      gameId,
    );

  const startWindow =
    evaluateGoLiveStartWindow(
      gameId,
    );

  const countdown =
    evaluateGoLiveCountdown(
      gameId,
    );

  const runtime =
    encoderRuntimeSnapshot(
      gameId,
    );

  const allowedState =
    session.status === "IDLE" ||
    session.status === "ARMED" ||
    session.status === "COMPLETE" ||
    session.status === "ERROR";

  const checks:
    GameDayGoLiveCheck[] = [
      {
        id:
          "STREAMING_PREFLIGHT",
        passed:
          streaming.ready,
        message:
          streaming.ready
            ? "Streaming readiness preflight passes."
            : "Streaming readiness preflight is blocked.",
      },
      {
        id:
          "START_WINDOW",
        passed:
          startWindow.withinWindow,
        message:
          startWindow.withinWindow
            ? "Go-live start window is open."
            : startWindow.tooEarly
              ? "Go-live start window has not opened yet."
              : "Go-live start window has expired.",
      },
      {
        id:
          "GO_LIVE_STATE",
        passed:
          allowedState,
        message:
          allowedState
            ? `Go-live state ${session.status} is eligible for preparation.`
            : `Go-live state ${session.status} is not eligible for a new start.`,
      },
      {
        id:
          "EMERGENCY_STOP",
        passed:
          session.status !==
          "EMERGENCY_STOPPED",
        message:
          session.status ===
            "EMERGENCY_STOPPED"
            ? "Emergency-stopped session must be reset."
            : "No emergency-stop lock is active.",
      },
      {
        id:
          "DEGRADED_INCIDENT",
        passed:
          session.status !==
          "DEGRADED",
        message:
          session.status ===
            "DEGRADED"
            ? session.degradationReason ??
              "Live incident remains degraded."
            : "No degraded live incident is active.",
      },
      {
        id:
          "RECOVERY_EXHAUSTION",
        passed:
          runtime.recovery.state !==
          "EXHAUSTED",
        message:
          runtime.recovery.state ===
            "EXHAUSTED"
            ? "Encoder automatic recovery is exhausted."
            : "Encoder recovery remains available.",
      },
      {
        id:
          "ENCODER_AVAILABILITY",
        passed:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR",
        message:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR"
            ? "Encoder is available for a new start."
            : `Encoder is currently ${runtime.session.status}.`,
      },
      {
        id:
          "SCHEDULE_COUNTDOWN",
        passed:
          !countdown.scheduled ||
          countdown.secondsUntilStart == null ||
          countdown.secondsUntilStart >=
            -Math.max(
              session.startWindowLateMinutes,
              0,
            ) *
              60,
        message:
          !countdown.scheduled
            ? "No scheduled start restricts this session."
            : `Scheduled start countdown is ${String(
                countdown.secondsUntilStart,
              )} seconds.`,
      },
    ];

  return {
    gameId,
    ready:
      checks.every(
        (check) =>
          check.passed,
      ),
    checkedAt:
      new Date().toISOString(),
    checks,
  };
}
