#include "FirmwareUpdateReporter.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>

namespace sportsos {

FirmwareUpdateReporter::FirmwareUpdateReporter(
    const FirmwareUpdateReporterConfig& config)
    : config_(config) {}

bool FirmwareUpdateReporter::report(
    const FirmwareUpdateOffer& offer,
    FirmwareUpdateState state,
    int progressPercent,
    const char* error) {
  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-firmware/deployments/report";

  if (!http.begin(url)) {
    return false;
  }

  http.addHeader(
      "Content-Type",
      "application/json");

  JsonDocument document;

  document["deviceId"] =
      config_.deviceId;

  document["releaseId"] =
      offer.releaseId;

  document["previousVersion"] =
      config_.currentVersion;

  document["targetVersion"] =
      offer.version;

  document["status"] =
      stateText(state);

  if (
      progressPercent >= 0
  ) {
    document["progressPercent"] =
        progressPercent;
  } else {
    document["progressPercent"] =
        nullptr;
  }

  document["error"] =
      error &&
      error[0] != '\0'
        ? error
        : nullptr;

  document["reportedAt"] =
      String(
          millis());

  String payload;

  serializeJson(
      document,
      payload);

  const int status =
      http.POST(
          payload);

  http.end();

  return
      status >= 200 &&
      status < 300;
}

const char*
FirmwareUpdateReporter::stateText(
    FirmwareUpdateState state) {
  return
      FirmwareUpdateContract::stateText(
          state);
}

}  // namespace sportsos
