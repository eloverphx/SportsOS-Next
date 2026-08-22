#include "DeviceEnrollment.h"

#include <ArduinoJson.h>
#include <stdio.h>
#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (
      destination == nullptr ||
      destinationSize == 0
  ) {
    return;
  }

  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }

  strncpy(
      destination,
      source,
      destinationSize - 1);

  destination[
      destinationSize - 1] = '\0';
}

}  // namespace

DeviceEnrollmentIdentity
DeviceEnrollment::buildIdentity(
    const char* deviceId) {
  DeviceEnrollmentIdentity identity{};

  copyText(
      identity.deviceId,
      sizeof(identity.deviceId),
      deviceId);

  copyText(
      identity.firmwareVersion,
      sizeof(identity.firmwareVersion),
      SPORTSOS_FIRMWARE_VERSION);

  const uint64_t chipId =
      ESP.getEfuseMac();

  snprintf(
      identity.chipId,
      sizeof(identity.chipId),
      "%012llX",
      chipId);

  return identity;
}

String DeviceEnrollment::buildFirstBootJson(
    const DeviceEnrollmentIdentity& identity) {
  JsonDocument document;

  document["deviceId"] =
      identity.deviceId;

  document["firmwareVersion"] =
      identity.firmwareVersion;

  document["chipId"] =
      identity.chipId;

  String json;

  serializeJson(
      document,
      json);

  return json;
}

String DeviceEnrollment::buildClaimVerificationJson(
    const char* claimToken) {
  JsonDocument document;

  document["claimToken"] =
      claimToken != nullptr
          ? claimToken
          : "";

  String json;

  serializeJson(
      document,
      json);

  return json;
}

}  // namespace sportsos
