import crypto from "node:crypto";

export type CommissioningSelfTestDispatch = {
  commandId: string;
  deviceId: string;
  status:
    | "PENDING"
    | "ACKNOWLEDGED"
    | "COMPLETED"
    | "FAILED";
  requestedAt: string;
  acknowledgedAt: string | null;
  completedAt: string | null;
  resultTestId: string | null;
};

const dispatches =
  new Map<
    string,
    CommissioningSelfTestDispatch
  >();

export function createCommissioningSelfTestDispatch(
  deviceId: string,
): CommissioningSelfTestDispatch {
  const commandId =
    `commissioning-self-test-${crypto.randomUUID()}`;

  const dispatch:
    CommissioningSelfTestDispatch = {
      commandId,
      deviceId,
      status:
        "PENDING",
      requestedAt:
        new Date().toISOString(),
      acknowledgedAt:
        null,
      completedAt:
        null,
      resultTestId:
        null,
    };

  dispatches.set(
    commandId,
    dispatch,
  );

  return {
    ...dispatch,
  };
}

export function getCommissioningSelfTestDispatch(
  commandId: string,
): CommissioningSelfTestDispatch | null {
  const dispatch =
    dispatches.get(
      commandId,
    );

  return dispatch
    ? { ...dispatch }
    : null;
}

export function acknowledgeCommissioningSelfTestDispatch(
  commandId: string,
  deviceId: string,
): CommissioningSelfTestDispatch {
  const dispatch =
    dispatches.get(
      commandId,
    );

  if (!dispatch) {
    throw new Error(
      "Self-test command not found.",
    );
  }

  if (
    dispatch.deviceId !==
    deviceId
  ) {
    throw new Error(
      "Self-test command belongs to another device.",
    );
  }

  dispatch.status =
    "ACKNOWLEDGED";
  dispatch.acknowledgedAt =
    new Date().toISOString();

  return {
    ...dispatch,
  };
}

export function completeCommissioningSelfTestDispatch(
  commandId: string,
  deviceId: string,
  resultTestId: string,
  passed: boolean,
): CommissioningSelfTestDispatch {
  const dispatch =
    dispatches.get(
      commandId,
    );

  if (!dispatch) {
    throw new Error(
      "Self-test command not found.",
    );
  }

  if (
    dispatch.deviceId !==
    deviceId
  ) {
    throw new Error(
      "Self-test command belongs to another device.",
    );
  }

  dispatch.status =
    passed
      ? "COMPLETED"
      : "FAILED";
  dispatch.completedAt =
    new Date().toISOString();
  dispatch.resultTestId =
    resultTestId;

  return {
    ...dispatch,
  };
}
