import {
  getEnrollment,
  isVerifiedDevice,
} from "./scoreboardDeviceEnrollment.js";

export type DeviceAuthorizationResult =
  | {
      ok: true;
    }
  | {
      ok: false;
      statusCode: 403;
      error: string;
    };

export function authorizeVerifiedScoreboardDevice(
  deviceId: string,
): DeviceAuthorizationResult {
  const record =
    getEnrollment(deviceId);

  if (!record) {
    return {
      ok: false,
      statusCode: 403,
      error:
        "Scoreboard device is not enrolled.",
    };
  }

  if (!isVerifiedDevice(deviceId)) {
    return {
      ok: false,
      statusCode: 403,
      error:
        `Scoreboard device is not verified. Current status: ${record.status}.`,
    };
  }

  return {
    ok: true,
  };
}
