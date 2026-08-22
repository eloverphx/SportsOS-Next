#include "FirmwareUpdateClient.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <string.h>

namespace sportsos {

FirmwareUpdateClient::FirmwareUpdateClient(
    const FirmwareUpdateClientConfig& config)
    : config_(config),
      state_(FirmwareUpdateCheckState::Idle),
      lastCheckMs_(0) {
  clearOffer();
}

void FirmwareUpdateClient::begin() {
  state_ =
      FirmwareUpdateCheckState::Idle;
  lastCheckMs_ =
      0;
  clearOffer();
}

void FirmwareUpdateClient::loop(
    bool wifiConnected,
    bool enrollmentVerified) {
  if (
      !wifiConnected ||
      !enrollmentVerified
  ) {
    return;
  }

  const unsigned long nowMs =
      millis();

  if (
      lastCheckMs_ != 0 &&
      nowMs - lastCheckMs_ <
        config_.checkIntervalMs
  ) {
    return;
  }

  lastCheckMs_ =
      nowMs;

  if (!checkForUpdate()) {
    state_ =
        FirmwareUpdateCheckState::TransportError;
  }
}

FirmwareUpdateCheckState
FirmwareUpdateClient::state() const {
  return state_;
}

bool FirmwareUpdateClient::updateAvailable() const {
  return
      state_ ==
      FirmwareUpdateCheckState::UpdateAvailable;
}

const FirmwareUpdateOffer&
FirmwareUpdateClient::offer() const {
  return offer_;
}

FirmwareDownloadResult
FirmwareUpdateClient::stageAvailableUpdate() {
  if (!updateAvailable()) {
    return
        FirmwareDownloadResult::TransportError;
  }

  return
      downloader_.downloadAndStage(
          config_.apiBaseUrl,
          offer_);
}

const FirmwareDownloadProgress&
FirmwareUpdateClient::downloadProgress() const {
  return downloader_.progress();
}

bool FirmwareUpdateClient::checkForUpdate() {
  state_ =
      FirmwareUpdateCheckState::Checking;

  HTTPClient http;

  String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-firmware/device-offer" +
      "?deviceId=" +
      config_.deviceId +
      "&currentVersion=" +
      config_.currentVersion +
      "&channel=" +
      config_.channel +
      "&target=" +
      config_.target;

  if (!http.begin(url)) {
    return false;
  }

  const int status =
      http.GET();

  const String response =
      http.getString();

  http.end();

  if (
      status < 200 ||
      status >= 300
  ) {
    return false;
  }

  JsonDocument document;

  if (
      deserializeJson(
        document,
        response)
  ) {
    state_ =
        FirmwareUpdateCheckState::InvalidOffer;

    return true;
  }

  const bool available =
      document["data"]["updateAvailable"] |
      false;

  if (!available) {
    clearOffer();
    state_ =
        FirmwareUpdateCheckState::NoUpdate;

    return true;
  }

  const JsonObject offer =
      document["data"]["offer"];

  const JsonObject release =
      offer["release"];

  const char* releaseId =
      release["releaseId"] | "";

  const char* version =
      release["version"] | "";

  const char* artifactUrl =
      offer["artifactUrl"] | "";

  const char* sha256 =
      release["firmwareSha256"] | "";

  const uint32_t size =
      release["firmwareSizeBytes"] | 0;

  const bool mandatory =
      release["mandatory"] | false;

  clearOffer();

  strlcpy(
      offer_.releaseId,
      releaseId,
      sizeof(
        offer_.releaseId));

  strlcpy(
      offer_.version,
      version,
      sizeof(
        offer_.version));

  strlcpy(
      offer_.firmwareUrl,
      artifactUrl,
      sizeof(
        offer_.firmwareUrl));

  strlcpy(
      offer_.firmwareSha256,
      sha256,
      sizeof(
        offer_.firmwareSha256));

  offer_.firmwareSizeBytes =
      size;

  offer_.mandatory =
      mandatory;

  if (
      !FirmwareUpdateContract::validateOffer(
        offer_)
  ) {
    clearOffer();

    state_ =
        FirmwareUpdateCheckState::InvalidOffer;

    return true;
  }

  state_ =
      FirmwareUpdateCheckState::UpdateAvailable;

  return true;
}

void FirmwareUpdateClient::clearOffer() {
  memset(
      &offer_,
      0,
      sizeof(
        offer_));
}

}  // namespace sportsos
