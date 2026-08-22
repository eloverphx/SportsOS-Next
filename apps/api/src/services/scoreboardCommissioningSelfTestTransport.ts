import type {
  CommissioningSelfTestDispatch,
} from "./scoreboardCommissioningSelfTestDispatch.js";

export type CommissioningSelfTestTransportCommand = {
  type:
    "COMMISSIONING_SELF_TEST";
  commandId: string;
  deviceId: string;
  requestedAt: string;
};

export function buildCommissioningSelfTestTransportCommand(
  dispatch:
    CommissioningSelfTestDispatch,
): CommissioningSelfTestTransportCommand {
  return {
    type:
      "COMMISSIONING_SELF_TEST",
    commandId:
      dispatch.commandId,
    deviceId:
      dispatch.deviceId,
    requestedAt:
      dispatch.requestedAt,
  };
}
