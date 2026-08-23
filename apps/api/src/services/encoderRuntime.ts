import {
  spawn,
  type ChildProcessByStdio,
} from "node:child_process";
import { recordEncoderAuditEvent } from "./encoderRuntimeAudit.js";

import type {
  Readable,
} from "node:stream";

import {
  getEncoderSession,
  markEncoderError,
  markEncoderLive,
  markEncoderStopped,
} from "./encoderSession.js";

import type {
  StreamDestinationProfile,
} from "./streamDestinationProfile.js";

import {
  resolveStreamCredential,
} from "./streamCredentialResolver.js";

export type EncoderRecoveryState =
  | "IDLE"
  | "SCHEDULED"
  | "RESTARTING"
  | "EXHAUSTED";

export type EncoderRecoverySnapshot = {
  gameId: string;
  state: EncoderRecoveryState;
  attempt: number;
  maxAttempts: number;
  nextRetryAt: string | null;
  lastFailureAt: string | null;
};

export type EncoderTelemetryHealth =
  | "IDLE"
  | "STARTING"
  | "HEALTHY"
  | "STALE"
  | "ERROR";

export type EncoderTelemetry = {
  gameId: string;
  health: EncoderTelemetryHealth;
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

type RuntimeEntry = {
  process:
    ChildProcessByStdio<
      null,
      Readable,
      Readable
    >;
  stopRequested:
    boolean;
  liveTimer:
    NodeJS.Timeout | null;
};

const runtimes =
  new Map<
    string,
    RuntimeEntry
  >();

const recovery =
  new Map<
    string,
    EncoderRecoverySnapshot
  >();

function maxRecoveryAttempts(): number {
  const parsed =
    Number.parseInt(
      process.env.SPORTSOS_ENCODER_MAX_RESTARTS ??
        "3",
      10,
    );

  return Number.isFinite(parsed) && parsed >= 0
    ? parsed
    : 3;
}

function recoveryBackoffMs(
  attempt: number,
): number {
  const base =
    Number.parseInt(
      process.env.SPORTSOS_ENCODER_RESTART_BACKOFF_MS ??
        "3000",
      10,
    );

  const safeBase =
    Number.isFinite(base) && base >= 500
      ? base
      : 3000;

  return Math.min(
    safeBase *
      Math.max(1, attempt),
    30000,
  );
}

export function getEncoderRecoverySnapshot(
  gameId: string,
): EncoderRecoverySnapshot {
  return recovery.get(gameId) ?? {
    gameId,
    state: "IDLE",
    attempt: 0,
    maxAttempts: maxRecoveryAttempts(),
    nextRetryAt: null,
    lastFailureAt: null,
  };
}

function resetEncoderRecovery(
  gameId: string,
): void {
  recovery.set(
    gameId,
    {
      gameId,
      state: "IDLE",
      attempt: 0,
      maxAttempts: maxRecoveryAttempts(),
      nextRetryAt: null,
      lastFailureAt: null,
    },
  );
}

const telemetry =
  new Map<
    string,
    EncoderTelemetry
  >();

function baseTelemetry(
  gameId: string,
): EncoderTelemetry {
  return {
    gameId,
    health: "IDLE",
    frame: null,
    fps: null,
    bitrateKbps: null,
    totalSizeBytes: null,
    outTimeMs: null,
    speed: null,
    lastProgressAt: null,
    startedAt: null,
    lastError: null,
  };
}

export function getEncoderTelemetry(
  gameId: string,
): EncoderTelemetry {
  const current =
    telemetry.get(
      gameId,
    ) ??
    baseTelemetry(
      gameId,
    );

  if (
    current.health === "HEALTHY" &&
    current.lastProgressAt &&
    Date.now() -
      Date.parse(
        current.lastProgressAt,
      ) >
      10000
  ) {
    return {
      ...current,
      health: "STALE",
    };
  }

  return {
    ...current,
  };
}


function resolveSourceUrl(
  gameId: string,
): string {
  const template =
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE
      ?.trim();

  const direct =
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL
      ?.trim();

  const value =
    template
      ? template.replaceAll(
          "{gameId}",
          encodeURIComponent(
            gameId,
          ),
        )
      : direct;

  if (!value) {
    throw new Error(
      "SPORTSOS_ENCODER_SOURCE_URL or SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE is required.",
    );
  }

  return value;
}

function buildOutputUrl(
  destination:
    StreamDestinationProfile,
  secret: string,
): string {
  const ingestUrl =
    destination.ingestUrl?.trim();

  if (!ingestUrl) {
    throw new Error(
      "Stream ingest URL is required.",
    );
  }

  if (
    destination.protocol ===
    "RTMP"
  ) {
    return (
      ingestUrl.replace(
        /\/+$/,
        "",
      ) +
      "/" +
      encodeURIComponent(
        secret,
      )
    );
  }

  const url =
    new URL(
      ingestUrl,
    );

  url.searchParams.set(
    "passphrase",
    secret,
  );

  return url.toString();
}

function buildFfmpegArgs(input: {
  destination:
    StreamDestinationProfile;
  sourceUrl: string;
  outputUrl: string;
}): string[] {
  const args = [
    "-hide_banner",
    "-nostdin",
    "-loglevel",
    "warning",
    "-progress",
    "pipe:1",
    "-nostats",
    "-i",
    input.sourceUrl,
    "-map",
    "0:v?",
    "-map",
    "0:a?",
    "-c",
    "copy",
  ];

  if (
    input.destination.protocol ===
    "RTMP"
  ) {
    args.push(
      "-f",
      "flv",
    );
  } else {
    args.push(
      "-f",
      "mpegts",
    );
  }

  args.push(
    input.outputUrl,
  );

  return args;
}

function parseNumeric(
  value: string,
): number | null {
  const parsed =
    Number(
      value,
    );

  return Number.isFinite(
    parsed,
  )
    ? parsed
    : null;
}

function parseProgressLine(
  gameId: string,
  line: string,
): void {
  const separator =
    line.indexOf("=");

  if (separator <= 0) {
    return;
  }

  const key =
    line.slice(
      0,
      separator,
    );

  const value =
    line.slice(
      separator + 1,
    );

  const current =
    telemetry.get(
      gameId,
    ) ??
    baseTelemetry(
      gameId,
    );

  const next: EncoderTelemetry = {
    ...current,
    gameId,
    health: "HEALTHY",
    lastProgressAt:
      new Date().toISOString(),
  };

  if (key === "frame") {
    next.frame =
      parseNumeric(
        value,
      );
  } else if (key === "fps") {
    next.fps =
      parseNumeric(
        value,
      );
  } else if (key === "bitrate") {
    next.bitrateKbps =
      parseNumeric(
        value.replace(
          /kbits\/s$/i,
          "",
        ),
      );
  } else if (key === "total_size") {
    next.totalSizeBytes =
      parseNumeric(
        value,
      );
  } else if (key === "out_time_ms") {
    const micros =
      parseNumeric(
        value,
      );

    next.outTimeMs =
      micros == null
        ? null
        : Math.floor(
            micros /
            1000,
          );
  } else if (key === "speed") {
    next.speed =
      parseNumeric(
        value.replace(
          /x$/i,
          "",
        ),
      );
  }

  telemetry.set(
    gameId,
    next,
  );
}

function sanitizedMessage(
  error: unknown,
): string {
  if (
    error instanceof Error
  ) {
    return error.message;
  }

  return "Encoder runtime error.";
}

export function isEncoderRuntimeActive(
  gameId: string,
): boolean {
  return runtimes.has(
    gameId,
  );
}

async function scheduleEncoderRestart(input: {
  gameId: string;
  destination: StreamDestinationProfile;
}): Promise<void> {
  const current =
    getEncoderRecoverySnapshot(
      input.gameId,
    );

  const nextAttempt =
    current.attempt + 1;

  if (
    nextAttempt >
    current.maxAttempts
  ) {
    recordEncoderAuditEvent({
      gameId:
        input.gameId,
      type:
        "RESTART_EXHAUSTED",
      attempt:
        current.attempt,
    });

    recovery.set(
      input.gameId,
      {
        ...current,
        state: "EXHAUSTED",
        nextRetryAt: null,
        lastFailureAt:
          new Date().toISOString(),
      },
    );

    return;
  }

  const delayMs =
    recoveryBackoffMs(
      nextAttempt,
    );

  const nextRetryAt =
    new Date(
      Date.now() +
        delayMs,
    ).toISOString();

  recordEncoderAuditEvent({
    gameId:
      input.gameId,
    type:
      "RESTART_SCHEDULED",
    attempt:
      nextAttempt,
    detail:
      `Retry in ${delayMs} ms.`,
  });

  recovery.set(
    input.gameId,
    {
      gameId:
        input.gameId,
      state:
        "SCHEDULED",
      attempt:
        nextAttempt,
      maxAttempts:
        current.maxAttempts,
      nextRetryAt,
      lastFailureAt:
        new Date().toISOString(),
    },
  );

  setTimeout(
    () => {
      const snapshot =
        getEncoderRecoverySnapshot(
          input.gameId,
        );

      if (
        snapshot.state !==
          "SCHEDULED" ||
        snapshot.attempt !==
          nextAttempt
      ) {
        return;
      }

      recordEncoderAuditEvent({
        gameId:
          input.gameId,
        type:
          "RESTARTING",
        attempt:
          nextAttempt,
      });

      recovery.set(
        input.gameId,
        {
          ...snapshot,
          state:
            "RESTARTING",
          nextRetryAt:
            null,
        },
      );

      void startEncoderRuntime({
        gameId:
          input.gameId,
        destination:
          input.destination,
        recoveryAttempt:
          true,
      }).catch(
        () => {
          void scheduleEncoderRestart(
            input,
          );
        },
      );
    },
    delayMs,
  );
}

export async function startEncoderRuntime(input: {
  gameId: string;
  destination:
    StreamDestinationProfile;
  recoveryAttempt?: boolean;
}): Promise<void> {
  if (
    runtimes.has(
      input.gameId,
    )
  ) {
    return;
  }

  if (!input.recoveryAttempt) {
    resetEncoderRecovery(
      input.gameId,
    );
  }

  const sourceUrl =
    resolveSourceUrl(
      input.gameId,
    );

  const secret =
    resolveStreamCredential(
      input.destination
        .credentialRef,
    );

  const outputUrl =
    buildOutputUrl(
      input.destination,
      secret,
    );

  const ffmpegPath =
    process.env
      .SPORTSOS_FFMPEG_PATH
      ?.trim() ||
    "ffmpeg";

  const args =
    buildFfmpegArgs({
      destination:
        input.destination,
      sourceUrl,
      outputUrl,
    });

  const child =
    spawn(
      ffmpegPath,
      args,
      {
        shell: false,
        stdio: [
          "ignore",
          "pipe",
          "pipe",
        ],
        env:
          process.env,
      },
    );

  const entry:
    RuntimeEntry = {
      process:
        child,
      stopRequested:
        false,
      liveTimer:
        null,
    };

  runtimes.set(
    input.gameId,
    entry,
  );

  recordEncoderAuditEvent({
    gameId:
      input.gameId,
    type:
      "RUNTIME_STARTED",
  });

  telemetry.set(
    input.gameId,
    {
      ...baseTelemetry(
        input.gameId,
      ),
      health: "STARTING",
      startedAt:
        new Date().toISOString(),
    },
  );

  let progressBuffer =
    "";

  child.stdout.on(
    "data",
    (
      chunk:
        Buffer,
    ) => {
      progressBuffer +=
        chunk.toString(
          "utf8",
        );

      const lines =
        progressBuffer.split(
          /\r?\n/,
        );

      progressBuffer =
        lines.pop() ??
        "";

      for (const line of lines) {
        parseProgressLine(
          input.gameId,
          line,
        );
      }
    },
  );

  let stderrTail =
    "";

  child.stderr.on(
    "data",
    (
      chunk:
        Buffer,
    ) => {
      const text =
        chunk.toString(
          "utf8",
        );

      stderrTail =
        (
          stderrTail +
          text
        ).slice(
          -2000,
        );
    },
  );

  child.once(
    "error",
    (error) => {
      if (
        entry.liveTimer
      ) {
        clearTimeout(
          entry.liveTimer,
        );
      }

      runtimes.delete(
        input.gameId,
      );

      recordEncoderAuditEvent({
        gameId:
          input.gameId,
        type:
          "RUNTIME_ERROR",
        detail:
          sanitizedMessage(
            error,
          ),
      });

      markEncoderError(
        input.gameId,
        sanitizedMessage(
          error,
        ),
      );
    },
  );

  child.once(
    "exit",
    (
      code,
      signal,
    ) => {
      if (
        entry.liveTimer
      ) {
        clearTimeout(
          entry.liveTimer,
        );
      }

      runtimes.delete(
        input.gameId,
      );

      if (
        entry.stopRequested
      ) {
        markEncoderStopped(
          input.gameId,
        );

        recordEncoderAuditEvent({
          gameId:
            input.gameId,
          type:
            "RUNTIME_STOPPED",
        });
        return;
      }

      const detail =
        stderrTail
          .trim()
          .split(
            "\n",
          )
          .slice(
            -2,
          )
          .join(
            " ",
          );

      markEncoderError(
        input.gameId,
        `FFmpeg exited unexpectedly (code=${String(
          code,
        )}, signal=${String(
          signal,
        )}).${
          detail
            ? ` ${detail}`
            : ""
        }`,
      );

      void scheduleEncoderRestart({
        gameId:
          input.gameId,
        destination:
          input.destination,
      });
    },
  );

  entry.liveTimer =
    setTimeout(
      () => {
        if (
          runtimes.get(
            input.gameId,
          ) ===
            entry &&
          child.exitCode ===
            null
        ) {
          markEncoderLive(
            input.gameId,
          );

          recordEncoderAuditEvent({
            gameId:
              input.gameId,
            type:
              "RUNTIME_LIVE",
          });
        }
      },
      2000,
    );
}

export async function stopEncoderRuntime(
  gameId: string,
): Promise<void> {
  const entry =
    runtimes.get(
      gameId,
    );

  if (!entry) {
    markEncoderStopped(
      gameId,
    );
    return;
  }

  entry.stopRequested =
    true;

  if (
    entry.liveTimer
  ) {
    clearTimeout(
      entry.liveTimer,
    );

    entry.liveTimer =
      null;
  }

  entry.process.kill(
    "SIGTERM",
  );

  setTimeout(
    () => {
      const current =
        runtimes.get(
          gameId,
        );

      if (
        current ===
          entry &&
        entry.process.exitCode ===
          null
      ) {
        entry.process.kill(
          "SIGKILL",
        );
      }
    },
    5000,
  );
}

export function encoderRuntimeSnapshot(
  gameId: string,
): {
  runtimeActive: boolean;
  session:
    ReturnType<
      typeof getEncoderSession
    >;
  telemetry:
    EncoderTelemetry;
  recovery:
    EncoderRecoverySnapshot;
} {
  return {
    runtimeActive:
      isEncoderRuntimeActive(
        gameId,
      ),
    session:
      getEncoderSession(
        gameId,
      ),
    telemetry:
      getEncoderTelemetry(
        gameId,
      ),
    recovery:
      getEncoderRecoverySnapshot(
        gameId,
      ),
  };
}
