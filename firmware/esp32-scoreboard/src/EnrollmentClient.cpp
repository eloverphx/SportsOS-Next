#include "EnrollmentClient.h"

#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFi.h>

namespace sportsos {

EnrollmentClient::EnrollmentClient(
    const EnrollmentClientConfig& config,
    const DeviceEnrollmentIdentity& identity)
    : config_(config),
      identity_(identity),
      state_(EnrollmentClientState::Idle),
      lastAttemptMs_(0) {}

void EnrollmentClient::begin() {
  state_ =
      EnrollmentClientState::Pending;

  lastAttemptMs_ = 0;
}

void EnrollmentClient::loop(
    bool wifiConnected) {
  if (!wifiConnected) {
    return;
  }

  if (
      state_ ==
      EnrollmentClientState::Verified ||
      state_ ==
      EnrollmentClientState::Rejected
  ) {
    return;
  }

  const unsigned long nowMs =
      millis();

  if (
      lastAttemptMs_ != 0 &&
      nowMs - lastAttemptMs_ <
          config_.retryIntervalMs
  ) {
    return;
  }

  lastAttemptMs_ =
      nowMs;

  if (
      state_ ==
      EnrollmentClientState::Idle ||
      state_ ==
      EnrollmentClientState::Pending ||
      state_ ==
      EnrollmentClientState::TransportError
  ) {
    if (!submitFirstBoot()) {
      state_ =
          EnrollmentClientState::TransportError;

      return;
    }

    refreshStatus();
  }
}

EnrollmentClientState
EnrollmentClient::state() const {
  return state_;
}

bool EnrollmentClient::isVerified() const {
  return
      state_ ==
      EnrollmentClientState::Verified;
}

bool EnrollmentClient::isRejected() const {
  return
      state_ ==
      EnrollmentClientState::Rejected;
}

bool EnrollmentClient::submitFirstBoot() {
  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-devices/enrollment/first-boot";

  if (!http.begin(url)) {
    return false;
  }

  http.addHeader(
      "Content-Type",
      "application/json");

  const String payload =
      DeviceEnrollment::buildFirstBootJson(
          identity_);

  const int status =
      http.POST(payload);

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
    return false;
  }

  const char* enrollmentStatus =
      document["data"]["status"] | "";

  applyServerStatus(
      String(enrollmentStatus));

  return true;
}

bool EnrollmentClient::refreshStatus() {
  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-devices/enrollment/" +
      identity_.deviceId;

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
    return false;
  }

  const char* enrollmentStatus =
      document["data"]["status"] | "";

  applyServerStatus(
      String(enrollmentStatus));

  return true;
}

void EnrollmentClient::applyServerStatus(
    const String& status) {
  if (status == "VERIFIED") {
    state_ =
        EnrollmentClientState::Verified;

    return;
  }

  if (status == "REJECTED") {
    state_ =
        EnrollmentClientState::Rejected;

    return;
  }

  state_ =
      EnrollmentClientState::Pending;
}

}  // namespace sportsos
