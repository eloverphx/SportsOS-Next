import fs from "node:fs";
import path from "node:path";

export type GoLiveSessionStatus =
  | "IDLE"
  | "ARMED"
  | "STARTING"
  | "LIVE"
  | "DEGRADED"
  | "STOPPING"
  | "COMPLETE"
  | "ERROR"
  | "EMERGENCY_STOPPED";

export type GoLiveSession = {
  gameId: string;
  status: GoLiveSessionStatus;
  armedAt: string | null;
  startedAt: string | null;
  liveAt: string | null;
  stoppedAt: string | null;
  completedAt: string | null;
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
  incidentAcknowledgedAt: string | null;
  incidentAcknowledgedBy: string | null;
  emergencyStoppedAt: string | null;
  emergencyStopReason: string | null;
};

type Store = {
  version: 1;
  sessions: GoLiveSession[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "go-live-sessions.json",
  );

let store =
  loadStore();

function loadStore(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.sessions,
      )
    ) {
      throw new Error(
        "Invalid go-live session store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      sessions: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

function replaceSession(
  session: GoLiveSession,
): GoLiveSession {
  store.sessions =
    store.sessions.filter(
      (item) =>
        item.gameId !==
        session.gameId,
    );

  store.sessions.push(
    session,
  );

  persistStore();

  return {
    ...session,
  };
}

export function getGoLiveSession(
  gameId: string,
): GoLiveSession {
  const existing =
    store.sessions.find(
      (item) =>
        item.gameId ===
        gameId,
    );

  if (existing) {
    return {
      ...existing,
    };
  }

  const now =
    new Date().toISOString();

  return {
    gameId,
    status:
      "IDLE",
    armedAt:
      null,
    startedAt:
      null,
    liveAt:
      null,
    stoppedAt:
      null,
    completedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
    scheduledStartAt:
      null,
    startWindowEarlyMinutes:
      15,
    startWindowLateMinutes:
      15,
    autoArmEnabled:
      false,
    autoArmLeadMinutes:
      30,
    healthHoldSeconds:
      10,
    healthySinceAt:
      null,
    degradedAt:
      null,
    degradationReason:
      null,
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
    emergencyStoppedAt:
      null,
    emergencyStopReason:
      null,
  };
}

export function configureGoLiveSchedule(input: {
  gameId: string;
  scheduledStartAt: string | null;
  startWindowEarlyMinutes?: number;
  startWindowLateMinutes?: number;
}): GoLiveSession {
  const current =
    getGoLiveSession(
      input.gameId,
    );

  const early =
    Number.isFinite(
      input.startWindowEarlyMinutes,
    )
      ? Math.max(
          0,
          Math.min(
            120,
            Math.floor(
              Number(
                input.startWindowEarlyMinutes,
              ),
            ),
          ),
        )
      : current.startWindowEarlyMinutes;

  const late =
    Number.isFinite(
      input.startWindowLateMinutes,
    )
      ? Math.max(
          0,
          Math.min(
            120,
            Math.floor(
              Number(
                input.startWindowLateMinutes,
              ),
            ),
          ),
        )
      : current.startWindowLateMinutes;

  const scheduledStartAt =
    input.scheduledStartAt
      ? new Date(
          input.scheduledStartAt,
        ).toISOString()
      : null;

  return replaceSession({
    ...current,
    scheduledStartAt,
    startWindowEarlyMinutes:
      early,
    startWindowLateMinutes:
      late,
    lastTransitionAt:
      new Date().toISOString(),
  });
}

export function configureGoLiveHealthHold(
  gameId: string,
  healthHoldSeconds: number,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const normalized =
    Math.max(
      0,
      Math.min(
        120,
        Math.floor(
          Number.isFinite(
            healthHoldSeconds,
          )
            ? healthHoldSeconds
            : current.healthHoldSeconds,
        ),
      ),
    );

  return replaceSession({
    ...current,
    healthHoldSeconds:
      normalized,
    healthySinceAt:
      null,
    lastTransitionAt:
      new Date().toISOString(),
  });
}

export function evaluateGoLiveHealthHold(input: {
  gameId: string;
  encoderLive: boolean;
  publishHealthy: boolean;
  now?: Date;
}): {
  readyToConfirm: boolean;
  healthySinceAt: string | null;
  holdSeconds: number;
  healthyForSeconds: number;
  remainingSeconds: number;
} {
  const current =
    getGoLiveSession(
      input.gameId,
    );

  const now =
    input.now ??
    new Date();

  if (
    !input.encoderLive ||
    !input.publishHealthy
  ) {
    if (
      current.healthySinceAt !==
      null
    ) {
      replaceSession({
        ...current,
        healthySinceAt:
          null,
      });
    }

    return {
      readyToConfirm:
        false,
      healthySinceAt:
        null,
      holdSeconds:
        current.healthHoldSeconds,
      healthyForSeconds:
        0,
      remainingSeconds:
        current.healthHoldSeconds,
    };
  }

  const healthySinceAt =
    current.healthySinceAt ??
    now.toISOString();

  if (
    current.healthySinceAt ===
    null
  ) {
    replaceSession({
      ...current,
      healthySinceAt,
    });
  }

  const elapsedMs =
    Math.max(
      0,
      now.getTime() -
        Date.parse(
          healthySinceAt,
        ),
    );

  const healthyForSeconds =
    Math.floor(
      elapsedMs /
        1000,
    );

  const remainingSeconds =
    Math.max(
      0,
      current.healthHoldSeconds -
        healthyForSeconds,
    );

  return {
    readyToConfirm:
      elapsedMs >=
      current.healthHoldSeconds *
        1000,
    healthySinceAt,
    holdSeconds:
      current.healthHoldSeconds,
    healthyForSeconds,
    remainingSeconds,
  };
}

export function configureGoLiveAutoArm(input: { gameId: string; enabled: boolean; leadMinutes?: number; }): GoLiveSession {
  const current = getGoLiveSession(input.gameId);
  const lead = Number.isFinite(input.leadMinutes) ? Math.max(0, Math.min(240, Math.floor(Number(input.leadMinutes)))) : current.autoArmLeadMinutes;
  return replaceSession({ ...current, autoArmEnabled: input.enabled, autoArmLeadMinutes: lead, lastTransitionAt: new Date().toISOString() });
}

export function evaluateGoLiveCountdown(gameId: string, now = new Date()) {
  const session = getGoLiveSession(gameId);
  if (!session.scheduledStartAt) return { scheduled:false, scheduledStartAt:null, secondsUntilStart:null, autoArmAt:null, autoArmDue:false };
  const start = Date.parse(session.scheduledStartAt);
  const arm = start - session.autoArmLeadMinutes * 60000;
  const nowMs = now.getTime();
  return { scheduled:true, scheduledStartAt:session.scheduledStartAt, secondsUntilStart:Math.ceil((start-nowMs)/1000), autoArmAt:new Date(arm).toISOString(), autoArmDue:session.autoArmEnabled && nowMs >= arm && nowMs <= start };
}

export function evaluateGoLiveStartWindow(
  gameId: string,
  now =
    new Date(),
): {
  scheduled: boolean;
  withinWindow: boolean;
  tooEarly: boolean;
  tooLate: boolean;
  opensAt: string | null;
  closesAt: string | null;
} {
  const session =
    getGoLiveSession(
      gameId,
    );

  if (
    !session.scheduledStartAt
  ) {
    return {
      scheduled: false,
      withinWindow: true,
      tooEarly: false,
      tooLate: false,
      opensAt: null,
      closesAt: null,
    };
  }

  const scheduledMs =
    Date.parse(
      session.scheduledStartAt,
    );

  const opensMs =
    scheduledMs -
    session.startWindowEarlyMinutes *
      60_000;

  const closesMs =
    scheduledMs +
    session.startWindowLateMinutes *
      60_000;

  const nowMs =
    now.getTime();

  return {
    scheduled: true,
    withinWindow:
      nowMs >=
        opensMs &&
      nowMs <=
        closesMs,
    tooEarly:
      nowMs <
      opensMs,
    tooLate:
      nowMs >
      closesMs,
    opensAt:
      new Date(
        opensMs,
      ).toISOString(),
    closesAt:
      new Date(
        closesMs,
      ).toISOString(),
  };
}

export function armGoLiveSession(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  if (
    current.status ===
      "ARMED" ||
    current.status ===
      "STARTING" ||
    current.status ===
      "LIVE"
  ) {
    return current;
  }

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "ARMED",
    armedAt:
      now,
    startedAt:
      null,
    liveAt:
      null,
    stoppedAt:
      null,
    completedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveStarting(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "STARTING",
    startedAt:
      current.startedAt ??
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveLive(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "LIVE",
    liveAt:
      current.liveAt ??
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveDegraded(
  gameId: string,
  reason: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "DEGRADED",
    degradedAt:
      current.degradedAt ??
      now,
    degradationReason:
      reason.trim() ||
      "Live broadcast degraded.",
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
    lastTransitionAt:
      now,
    lastError:
      reason.trim() ||
      "Live broadcast degraded.",
  });
}

export function acknowledgeGoLiveIncident(
  gameId: string,
  operator: string | null,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  if (
    current.status !==
    "DEGRADED"
  ) {
    return current;
  }

  return replaceSession({
    ...current,
    incidentAcknowledgedAt:
      new Date().toISOString(),
    incidentAcknowledgedBy:
      operator?.trim() ||
      null,
  });
}

export function clearGoLiveIncidentAcknowledgement(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
    emergencyStoppedAt:
      null,
    emergencyStopReason:
      null,
  });
}

export function clearGoLiveDegraded(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "LIVE",
    degradedAt:
      null,
    degradationReason:
      null,
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      null,
  });
}

export function markGoLiveStopping(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "STOPPING",
    stoppedAt:
      null,
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      null,
  });
}

export function completeGoLiveSession(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "COMPLETE",
    stoppedAt:
      now,
    completedAt:
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveError(
  gameId: string,
  message: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "ERROR",
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      message.trim() ||
      "Go-live session error.",
  });
}

export function markGoLiveEmergencyStopped(
  gameId: string,
  reason: string | null,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "EMERGENCY_STOPPED",
    stoppedAt:
      now,
    emergencyStoppedAt:
      now,
    emergencyStopReason:
      reason?.trim() ||
      "Emergency broadcast stop.",
    lastTransitionAt:
      now,
    lastError:
      reason?.trim() ||
      "Emergency broadcast stop.",
  });
}

export function resetGoLiveSession(
  gameId: string,
): GoLiveSession {
  const now =
    new Date().toISOString();

  return replaceSession({
    gameId,
    status:
      "IDLE",
    armedAt:
      null,
    startedAt:
      null,
    liveAt:
      null,
    stoppedAt:
      null,
    completedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
    scheduledStartAt:
      null,
    startWindowEarlyMinutes:
      15,
    startWindowLateMinutes:
      15,
    autoArmEnabled:
      false,
    autoArmLeadMinutes:
      30,
    healthHoldSeconds:
      10,
    healthySinceAt:
      null,
    degradedAt:
      null,
    degradationReason:
      null,
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
    emergencyStoppedAt:
      null,
    emergencyStopReason:
      null,
  });
}
