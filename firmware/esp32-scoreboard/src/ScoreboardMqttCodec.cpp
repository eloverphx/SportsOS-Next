#include "ScoreboardMqttCodec.h"

#include <ArduinoJson.h>
#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (destinationSize == 0) {
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

void setError(
    char* error,
    size_t errorSize,
    const char* message) {
  copyText(
      error,
      errorSize,
      message);
}

CommandType parseCommandType(
    const char* type) {
  if (type == nullptr) {
    return CommandType::Unknown;
  }

  if (strcmp(type, "SET_GAME") == 0) {
    return CommandType::SetGame;
  }

  if (strcmp(type, "SET_SCORE") == 0) {
    return CommandType::SetScore;
  }

  if (strcmp(type, "SET_CLOCK") == 0) {
    return CommandType::SetClock;
  }

  if (strcmp(type, "SET_PERIOD") == 0) {
    return CommandType::SetPeriod;
  }

  if (strcmp(type, "HORN") == 0) {
    return CommandType::Horn;
  }

  if (strcmp(type, "SYNC_STATE") == 0) {
    return CommandType::SyncState;
  }

  return CommandType::Unknown;
}

const char* statusText(
    CommandStatus status) {
  switch (status) {
    case CommandStatus::Accepted:
      return "ACCEPTED";
    case CommandStatus::Rejected:
      return "REJECTED";
    case CommandStatus::Applied:
      return "APPLIED";
    default:
      return "REJECTED";
  }
}

void encodeClock(
    JsonObject object,
    const ClockState& clock) {
  object["remainingMs"] =
      clock.remainingMs;
  object["running"] =
      clock.running;
}

void encodeStateFields(
    JsonObject object,
    const ScoreboardState& state) {
  object["protocolVersion"] =
      state.protocolVersion;
  object["deviceId"] =
      state.deviceId;

  if (state.hasGame) {
    object["gameId"] =
        state.gameId;
  } else {
    object["gameId"] = nullptr;
  }

  object["homeScore"] =
      state.homeScore;
  object["awayScore"] =
      state.awayScore;

  if (state.hasPeriod) {
    object["period"] =
        state.period;
  } else {
    object["period"] = nullptr;
  }

  JsonObject clock =
      object["clock"]
          .to<JsonObject>();

  encodeClock(
      clock,
      state.clock);

  object["hornActive"] =
      state.hornActive;
}

bool serialize(
    JsonDocument& document,
    char* output,
    size_t outputSize) {
  if (
      output == nullptr ||
      outputSize == 0
  ) {
    return false;
  }

  const size_t required =
      measureJson(document) + 1;

  if (required > outputSize) {
    output[0] = '\0';
    return false;
  }

  serializeJson(
      document,
      output,
      outputSize);

  return true;
}

}  // namespace

bool ScoreboardMqttCodec::parseCommand(
    const char* json,
    ParsedCommand& command,
    char* error,
    size_t errorSize) {
  memset(
      &command,
      0,
      sizeof(command));

  if (json == nullptr) {
    setError(
        error,
        errorSize,
        "Command JSON is null.");
    return false;
  }

  JsonDocument document;

  const DeserializationError parseError =
      deserializeJson(
          document,
          json);

  if (parseError) {
    setError(
        error,
        errorSize,
        "Invalid JSON.");
    return false;
  }

  command.protocolVersion =
      document["protocolVersion"] | 0;

  copyText(
      command.commandId,
      sizeof(command.commandId),
      document["commandId"] | "");

  command.type =
      parseCommandType(
          document["type"] | "");

  if (
      command.protocolVersion !=
      SCOREBOARD_PROTOCOL_VERSION
  ) {
    setError(
        error,
        errorSize,
        "Protocol version mismatch.");
    return false;
  }

  if (command.commandId[0] == '\0') {
    setError(
        error,
        errorSize,
        "commandId is required.");
    return false;
  }

  if (
      command.type ==
      CommandType::Unknown
  ) {
    setError(
        error,
        errorSize,
        "Unsupported command type.");
    return false;
  }

  switch (command.type) {
    case CommandType::SetGame: {
      const char* gameId =
          document["gameId"];

      command.hasGame =
          gameId != nullptr &&
          gameId[0] != '\0';

      copyText(
          command.gameId,
          sizeof(command.gameId),
          command.hasGame
              ? gameId
              : "");

      break;
    }

    case CommandType::SetScore:
      command.homeScore =
          document["homeScore"] | 0;
      command.awayScore =
          document["awayScore"] | 0;
      break;

    case CommandType::SetClock:
      command.remainingMs =
          document["remainingMs"] | 0;
      command.clockRunning =
          document["running"] | false;
      break;

    case CommandType::SetPeriod:
      command.hasPeriod =
          !document["period"].isNull();

      command.period =
          command.hasPeriod
              ? document["period"].as<uint8_t>()
              : 0;

      break;

    case CommandType::Horn:
      command.hornActive =
          document["active"] | false;
      break;

    case CommandType::SyncState: {
      JsonObjectConst snapshot =
          document["snapshot"]
              .as<JsonObjectConst>();

      if (snapshot.isNull()) {
        setError(
            error,
            errorSize,
            "SYNC_STATE snapshot is required.");
        return false;
      }

      command.syncState.protocolVersion =
          snapshot["protocolVersion"] | 0;

      copyText(
          command.syncState.deviceId,
          sizeof(command.syncState.deviceId),
          snapshot["deviceId"] | "");

      const char* gameId =
          snapshot["gameId"];

      command.syncState.hasGame =
          gameId != nullptr &&
          gameId[0] != '\0';

      copyText(
          command.syncState.gameId,
          sizeof(command.syncState.gameId),
          command.syncState.hasGame
              ? gameId
              : "");

      command.syncState.homeScore =
          snapshot["homeScore"] | 0;
      command.syncState.awayScore =
          snapshot["awayScore"] | 0;

      command.syncState.hasPeriod =
          !snapshot["period"].isNull();

      command.syncState.period =
          command.syncState.hasPeriod
              ? snapshot["period"]
                    .as<uint8_t>()
              : 0;

      JsonObjectConst clock =
          snapshot["clock"]
              .as<JsonObjectConst>();

      command.syncState.clock.remainingMs =
          clock["remainingMs"] | 0;
      command.syncState.clock.running =
          clock["running"] | false;

      command.syncState.hornActive =
          snapshot["hornActive"] | false;

      break;
    }

    case CommandType::Unknown:
    default:
      setError(
          error,
          errorSize,
          "Unsupported command type.");
      return false;
  }

  setError(
      error,
      errorSize,
      "");

  return true;
}

bool ScoreboardMqttCodec::encodeState(
    const ScoreboardState& state,
    const char* updatedAt,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  JsonObject root =
      document.to<JsonObject>();

  encodeStateFields(
      root,
      state);

  root["updatedAt"] =
      updatedAt != nullptr
          ? updatedAt
          : "";

  return serialize(
      document,
      output,
      outputSize);
}

bool ScoreboardMqttCodec::encodeAcknowledgement(
    const MqttAcknowledgement& acknowledgement,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  document["commandId"] =
      acknowledgement.commandId;
  document["status"] =
      statusText(
          acknowledgement.status);

  if (
      acknowledgement.message[0] != '\0'
  ) {
    document["message"] =
        acknowledgement.message;
  } else {
    document["message"] = nullptr;
  }

  document["acknowledgedAt"] =
      acknowledgement.acknowledgedAt;

  return serialize(
      document,
      output,
      outputSize);
}

bool ScoreboardMqttCodec::encodePresence(
    const MqttPresence& presence,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  document["online"] =
      presence.online;
  document["reportedAt"] =
      presence.reportedAt;

  return serialize(
      document,
      output,
      outputSize);
}

bool ScoreboardMqttCodec::encodeTelemetry(
    const MqttTelemetry& telemetry,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  document["firmwareVersion"] =
      telemetry.firmwareVersion;
  document["ipAddress"] =
      telemetry.ipAddress;
  document["wifiRssi"] =
      telemetry.wifiRssi;
  document["uptimeSeconds"] =
      telemetry.uptimeSeconds;
  document["freeHeapBytes"] =
      telemetry.freeHeapBytes;
  document["reportedAt"] =
      telemetry.reportedAt;

  return serialize(
      document,
      output,
      outputSize);
}

}  // namespace sportsos
