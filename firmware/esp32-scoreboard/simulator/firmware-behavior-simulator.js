"use strict";

function clampNonNegativeInteger(value) {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.max(0, Math.floor(value));
}

function buildNumericSnapshot(frame) {
  const totalSeconds =
    Math.floor(
      clampNonNegativeInteger(frame.remainingMs) /
        1000,
    );

  return {
    homeScore:
      clampNonNegativeInteger(frame.homeScore),
    awayScore:
      clampNonNegativeInteger(frame.awayScore),
    period:
      frame.hasPeriod
        ? clampNonNegativeInteger(frame.period)
        : null,
    clockMinutes:
      Math.floor(totalSeconds / 60),
    clockSeconds:
      totalSeconds % 60,
    clockRunning:
      Boolean(frame.clockRunning),
    hornActive:
      Boolean(frame.hornActive),
    health:
      frame.health ?? "Normal",
  };
}

function renderSevenSegment(snapshot) {
  const two = (value) =>
    String(value).padStart(2, "0");

  return {
    home: two(snapshot.homeScore),
    away: two(snapshot.awayScore),
    period:
      snapshot.period === null
        ? "-"
        : String(snapshot.period),
    clock:
      `${two(snapshot.clockMinutes)}:${two(snapshot.clockSeconds)}`,
    running:
      snapshot.clockRunning,
    horn:
      snapshot.hornActive,
    health:
      snapshot.health,
  };
}

function tickFrame(frame, elapsedMs) {
  if (!frame.clockRunning) {
    return { ...frame };
  }

  const next =
    Math.max(
      0,
      clampNonNegativeInteger(frame.remainingMs) -
        clampNonNegativeInteger(elapsedMs),
    );

  return {
    ...frame,
    remainingMs: next,
    clockRunning: next > 0,
  };
}


function buildDiagnosticSnapshot({
  uptimeSeconds = 0,
  wifiRssi = 0,
  freeHeapBytes = 0,
  wifiConnected = false,
  mqttConnected = false,
  connectionState = "OFFLINE",
  connectivityHealth = "HEALTHY",
  deviceId = "",
  gameId = null,
}) {
  return {
    uptimeSeconds:
      clampNonNegativeInteger(uptimeSeconds),
    wifiRssi:
      Number.isFinite(wifiRssi)
        ? Math.trunc(wifiRssi)
        : 0,
    freeHeapBytes:
      clampNonNegativeInteger(freeHeapBytes),
    wifiConnected:
      Boolean(wifiConnected),
    mqttConnected:
      Boolean(mqttConnected),
    authoritativeStateStale:
      connectivityHealth ===
      "STALE_AUTHORITATIVE_STATE",
    recoveryRequired:
      connectivityHealth ===
      "RECOVERY_REQUIRED",
    connectionState,
    connectivityHealth,
    deviceId,
    gameId:
      gameId || null,
  };
}


function evaluateVerifiedRuntimeGate(
  enrollmentState,
) {
  if (enrollmentState === "VERIFIED") {
    return {
      state: "ALLOWED",
      allowAuthoritativeRuntime: true,
    };
  }

  if (enrollmentState === "REJECTED") {
    return {
      state: "REJECTED",
      allowAuthoritativeRuntime: false,
    };
  }

  return {
    state: "WAITING_FOR_ENROLLMENT",
    allowAuthoritativeRuntime: false,
  };
}


function evaluateFirmwareUpdateOffer({
  enrollmentStatus,
  currentVersion,
  release,
}) {
  if (enrollmentStatus !== "VERIFIED") {
    return {
      state: "BLOCKED_UNVERIFIED",
      updateAvailable: false,
    };
  }

  if (!release) {
    return {
      state: "NO_UPDATE",
      updateAvailable: false,
    };
  }

  if (
    !release.releaseId ||
    !release.version ||
    !release.firmwareSha256 ||
    release.firmwareSha256.length !== 64 ||
    !Number.isFinite(
      release.firmwareSizeBytes,
    ) ||
    release.firmwareSizeBytes <= 0
  ) {
    return {
      state: "INVALID_OFFER",
      updateAvailable: false,
    };
  }

  if (release.version === currentVersion) {
    return {
      state: "NO_UPDATE",
      updateAvailable: false,
    };
  }

  return {
    state: "UPDATE_AVAILABLE",
    updateAvailable: true,
    releaseId: release.releaseId,
    version: release.version,
  };
}


function verifyFirmwareDownload({
  expectedSize,
  actualSize,
  expectedSha256,
  actualSha256,
}) {
  if (
    !Number.isFinite(expectedSize) ||
    expectedSize <= 0 ||
    actualSize !== expectedSize
  ) {
    return {
      ok: false,
      state: "FAILED",
      reason: "SIZE_MISMATCH",
    };
  }

  if (
    typeof expectedSha256 !== "string" ||
    expectedSha256.length !== 64 ||
    typeof actualSha256 !== "string" ||
    actualSha256.toLowerCase() !==
      expectedSha256.toLowerCase()
  ) {
    return {
      ok: false,
      state: "FAILED",
      reason: "SHA256_MISMATCH",
    };
  }

  return {
    ok: true,
    state: "READY_TO_INSTALL",
    reason: null,
  };
}

module.exports = {
  buildNumericSnapshot,
  renderSevenSegment,
  tickFrame,
  buildDiagnosticSnapshot,
  evaluateVerifiedRuntimeGate,
  evaluateFirmwareUpdateOffer,
  verifyFirmwareDownload,
};
