import type {
  FastifyInstance,
} from "fastify";

import {
  evaluateScoreboardControlReadiness,
} from "./scoreboardControlReadiness.js";

import {
  listScoreboardReliabilityClassifications,
} from "./scoreboardReadinessReliability.js";

import {
  getScoreboardCommissioning,
  updateScoreboardCommissioningStep,
  type CommissioningStepId,
  type ScoreboardDeviceCommissioning,
} from "./scoreboardDeviceCommissioning.js";

type ValidationResult = {
  step: CommissioningStepId;
  complete: boolean;
  note: string;
};

type Assignment = {
  gameId: string;
  deviceId: string;
};

function normalizeDeviceId(
  value: unknown,
): string | null {
  if (
    typeof value !== "string" ||
    !value.trim()
  ) {
    return null;
  }

  return value.trim();
}

async function getJson(
  app: FastifyInstance,
  url: string,
): Promise<unknown | null> {
  const response =
    await app.inject({
      method: "GET",
      url,
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return null;
  }

  try {
    return response.json();
  } catch {
    return null;
  }
}

function containsDevice(
  payload: unknown,
  deviceId: string,
): boolean {
  const seen =
    new Set<unknown>();

  function visit(
    value: unknown,
  ): boolean {
    if (
      value === null ||
      value === undefined ||
      seen.has(value)
    ) {
      return false;
    }

    if (
      typeof value === "string"
    ) {
      return value ===
        deviceId;
    }

    if (
      typeof value !== "object"
    ) {
      return false;
    }

    seen.add(
      value,
    );

    if (
      Array.isArray(
        value,
      )
    ) {
      return value.some(
        visit,
      );
    }

    const record =
      value as Record<
        string,
        unknown
      >;

    for (
      const key of [
        "deviceId",
        "device_id",
        "hardwareId",
        "hardware_id",
        "identifier",
        "serialNumber",
        "serial_number",
      ]
    ) {
      if (
        normalizeDeviceId(
          record[key],
        ) ===
        deviceId
      ) {
        return true;
      }
    }

    return Object.values(
      record,
    ).some(
      visit,
    );
  }

  return visit(
    payload,
  );
}

async function validateEnrollment(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const endpoints = [
    "/scoreboard-device-enrollment",
    "/scoreboard-devices/enrollment",
    "/scoreboard-devices",
  ];

  for (const endpoint of endpoints) {
    const payload =
      await getJson(
        app,
        endpoint,
      );

    if (
      payload &&
      containsDevice(
        payload,
        deviceId,
      )
    ) {
      return {
        step: "ENROLLED",
        complete: true,
        note:
          `Device found through ${endpoint}.`,
      };
    }
  }

  return {
    step: "ENROLLED",
    complete: false,
    note:
      "Device enrollment could not be confirmed.",
  };
}

async function validateVerification(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const endpoints = [
    "/scoreboard-devices",
    "/scoreboard-device-enrollment",
  ];

  for (const endpoint of endpoints) {
    const payload =
      await getJson(
        app,
        endpoint,
      );

    if (!payload) {
      continue;
    }

    const text =
      JSON.stringify(
        payload,
      );

    if (
      text.includes(
        deviceId,
      ) &&
      /verified/i.test(
        text,
      )
    ) {
      return {
        step:
          "VERIFIED",
        complete:
          true,
        note:
          `Verified device state found through ${endpoint}.`,
      };
    }
  }

  return {
    step:
      "VERIFIED",
    complete:
      false,
    note:
      "Verified-device state could not be confirmed.",
  };
}

async function validateAssignment(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const payload =
    await getJson(
      app,
      "/scoreboard-devices/assignments",
    ) as
      | {
          data?: {
            assignments?: Assignment[];
          };
          assignments?: Assignment[];
        }
      | null;

  const assignments =
    payload?.data?.assignments ??
    payload?.assignments ??
    [];

  const assignment =
    assignments.find(
      (item) =>
        item.deviceId ===
        deviceId,
    );

  return {
    step:
      "ASSIGNED",
    complete:
      Boolean(
        assignment,
      ),
    note:
      assignment
        ? `Assigned to game ${assignment.gameId}.`
        : "No scoreboard assignment found.",
  };
}

async function validateConnectivity(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const readiness =
    await evaluateScoreboardControlReadiness(
      deviceId,
    );

  return {
    step:
      "CONNECTIVITY",
    complete:
      Boolean(
        readiness.lastHeartbeatAt,
      ),
    note:
      readiness.lastHeartbeatAt
        ? `Heartbeat observed at ${readiness.lastHeartbeatAt}.`
        : readiness.reason ??
          "No device heartbeat observed.",
  };
}

async function validateReadiness(
  deviceId: string,
): Promise<ValidationResult> {
  const readiness =
    await evaluateScoreboardControlReadiness(
      deviceId,
    );

  return {
    step:
      "READINESS",
    complete:
      readiness.ready,
    note:
      readiness.ready
        ? `Heartbeat age ${readiness.heartbeatAgeMs ?? 0}ms is within ${readiness.thresholdMs}ms threshold.`
        : `BLOCKED: ${readiness.reason ?? "Device is not ready."}`,
  };
}

function validateReliability(
  deviceId: string,
): ValidationResult {
  const classification =
    listScoreboardReliabilityClassifications()
      .find(
        (item) =>
          item.deviceId ===
          deviceId,
      );

  if (!classification) {
    return {
      step:
        "READINESS",
      complete:
        false,
      note:
        "BLOCKED: Reliability history is unavailable.",
    };
  }

  return {
    step:
      "READINESS",
    complete:
      classification.risk ===
        "HEALTHY" ||
      classification.risk ===
        "WATCH",
    note:
      classification.risk ===
        "HEALTHY" ||
      classification.risk ===
        "WATCH"
        ? `Reliability classification is ${classification.risk}.`
        : `BLOCKED: Reliability classification is ${classification.risk}.`,
  };
}

async function validateFirmware(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const endpoints = [
    `/scoreboard-firmware/device-offer?deviceId=${encodeURIComponent(deviceId)}`,
    `/scoreboard-firmware-releases/device-offer?deviceId=${encodeURIComponent(deviceId)}`,
    "/scoreboard-firmware-releases",
  ];

  for (const endpoint of endpoints) {
    const payload =
      await getJson(
        app,
        endpoint,
      );

    if (!payload) {
      continue;
    }

    const text =
      JSON.stringify(
        payload,
      );

    if (
      text.includes(
        deviceId,
      ) ||
      /firmware|release|version/i.test(
        text,
      )
    ) {
      return {
        step:
          "FIRMWARE",
        complete:
          true,
        note:
          `Firmware state confirmed through ${endpoint}.`,
      };
    }
  }

  return {
    step:
      "FIRMWARE",
    complete:
      false,
    note:
      "Approved firmware state could not be confirmed automatically.",
  };
}

function preserveManualStep(
  record:
    ScoreboardDeviceCommissioning,
  step:
    CommissioningStepId,
): ValidationResult {
  const current =
    record.steps.find(
      (item) =>
        item.id ===
        step,
    );

  return {
    step,
    complete:
      current?.complete ??
      false,
    note:
      current?.note ??
      (
        step ===
          "FLASHED"
          ? "Manual confirmation required after firmware flashing."
          : "Manual confirmation required after device provisioning."
      ),
  };
}

export async function validateScoreboardCommissioning(
  app: FastifyInstance,
  deviceId: string,
): Promise<ScoreboardDeviceCommissioning> {
  const record =
    getScoreboardCommissioning(
      deviceId,
    );

  if (!record) {
    throw new Error(
      "Commissioning record not found.",
    );
  }

  const results:
    ValidationResult[] = [
      preserveManualStep(
        record,
        "FLASHED",
      ),
      preserveManualStep(
        record,
        "PROVISIONED",
      ),
      await validateEnrollment(
        app,
        deviceId,
      ),
      await validateVerification(
        app,
        deviceId,
      ),
      await validateAssignment(
        app,
        deviceId,
      ),
      await validateConnectivity(
        app,
        deviceId,
      ),
    ];

  const directReadiness =
    await validateReadiness(
      deviceId,
    );

  const reliabilityReadiness =
    validateReliability(
      deviceId,
    );

  results.push({
    step:
      "READINESS",
    complete:
      directReadiness.complete &&
      reliabilityReadiness.complete,
    note:
      directReadiness.complete &&
      reliabilityReadiness.complete
        ? `${directReadiness.note} ${reliabilityReadiness.note}`
        : [
            directReadiness.note,
            reliabilityReadiness.note,
          ].join(
            " ",
          ),
  });

  results.push(
    await validateFirmware(
      app,
      deviceId,
    ),
  );

  for (const result of results) {
    updateScoreboardCommissioningStep({
      deviceId,
      step:
        result.step,
      complete:
        result.complete,
      note:
        result.note,
    });
  }

  const refreshed =
    getScoreboardCommissioning(
      deviceId,
    );

  if (!refreshed) {
    throw new Error(
      "Commissioning record disappeared during validation.",
    );
  }

  const prerequisitesPassed =
    refreshed.steps
      .filter(
        (step) =>
          step.id !==
          "GAME_READY",
      )
      .every(
        (step) =>
          step.complete,
      );

  updateScoreboardCommissioningStep({
    deviceId,
    step:
      "GAME_READY",
    complete:
      prerequisitesPassed,
    note:
      prerequisitesPassed
        ? "All commissioning validations passed."
        : "Commissioning prerequisites are incomplete.",
  });

  const finalRecord =
    getScoreboardCommissioning(
      deviceId,
    );

  if (!finalRecord) {
    throw new Error(
      "Unable to load final commissioning result.",
    );
  }

  return finalRecord;
}
