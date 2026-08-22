#include "ScoreboardControlInputClient.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>

namespace sportsos {

ScoreboardControlInputClient::ScoreboardControlInputClient(
    const ScoreboardControlInputClientConfig& config)
    : config_(config),
      lastReason_(""),
      authoritativeGameId_("") {}

ScoreboardControlSubmitResult
ScoreboardControlInputClient::submit(
    ScoreboardControlInputType type,
    uint32_t sequence,
    unsigned long occurredAtMs) {
  lastReason_ = "";
  authoritativeGameId_ = "";

  if (
      config_.apiBaseUrl == nullptr ||
      config_.deviceId == nullptr ||
      config_.deviceId[0] == '\0'
  ) {
    return ScoreboardControlSubmitResult::TransportError;
  }

  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-control-inputs";

  if (!http.begin(url)) {
    return ScoreboardControlSubmitResult::TransportError;
  }

  http.addHeader(
      "Content-Type",
      "application/json");

  JsonDocument document;

  document["protocolVersion"] =
      CONTROL_INPUT_PROTOCOL_VERSION;

  document["inputId"] =
      createInputId(
          sequence,
          occurredAtMs);

  document["deviceId"] =
      config_.deviceId;

  document["type"] =
      ScoreboardControlInput::typeText(
          type);

  document["occurredAt"] =
      String(occurredAtMs);

  document["sequence"] =
      sequence;

  String payload;

  serializeJson(
      document,
      payload);

  const int status =
      http.POST(
          payload);

  const String response =
      http.getString();

  http.end();

  if (
      status < 200 ||
      status >= 300
  ) {
    return ScoreboardControlSubmitResult::TransportError;
  }

  JsonDocument responseDocument;

  const auto error =
      deserializeJson(
          responseDocument,
          response);

  if (error) {
    return ScoreboardControlSubmitResult::InvalidResponse;
  }

  const char* disposition =
      responseDocument["data"]["disposition"] |
      "";

  lastReason_ =
      String(
          responseDocument["data"]["reason"] |
          "");

  authoritativeGameId_ =
      String(
          responseDocument["data"]["authoritativeGameId"] |
          "");

  if (
      strcmp(
          disposition,
          "ACCEPTED") == 0
  ) {
    return ScoreboardControlSubmitResult::Accepted;
  }

  if (
      strcmp(
          disposition,
          "REJECTED") == 0
  ) {
    return ScoreboardControlSubmitResult::Rejected;
  }

  if (
      strcmp(
          disposition,
          "IGNORED_DUPLICATE") == 0
  ) {
    return ScoreboardControlSubmitResult::IgnoredDuplicate;
  }

  return ScoreboardControlSubmitResult::InvalidResponse;
}

const String&
ScoreboardControlInputClient::lastReason() const {
  return lastReason_;
}

const String&
ScoreboardControlInputClient::authoritativeGameId() const {
  return authoritativeGameId_;
}

String
ScoreboardControlInputClient::createInputId(
    uint32_t sequence,
    unsigned long occurredAtMs) const {
  return
      String(config_.deviceId) +
      "-" +
      String(sequence) +
      "-" +
      String(occurredAtMs);
}

}  // namespace sportsos
