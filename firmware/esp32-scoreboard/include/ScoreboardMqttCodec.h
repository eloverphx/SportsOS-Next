#pragma once

#include <stddef.h>
#include <stdint.h>

#include "ScoreboardProtocol.h"

namespace sportsos {

struct MqttAcknowledgement {
  char commandId[64];
  CommandStatus status;
  char message[128];
  char acknowledgedAt[40];
};

struct MqttPresence {
  bool online;
  char reportedAt[40];
};

struct MqttTelemetry {
  char firmwareVersion[32];
  char ipAddress[48];
  int32_t wifiRssi;
  uint32_t uptimeSeconds;
  uint32_t freeHeapBytes;
  char reportedAt[40];
};

class ScoreboardMqttCodec {
 public:
  static bool parseCommand(
      const char* json,
      ParsedCommand& command,
      char* error,
      size_t errorSize);

  static bool encodeState(
      const ScoreboardState& state,
      const char* updatedAt,
      char* output,
      size_t outputSize);

  static bool encodeAcknowledgement(
      const MqttAcknowledgement& acknowledgement,
      char* output,
      size_t outputSize);

  static bool encodePresence(
      const MqttPresence& presence,
      char* output,
      size_t outputSize);

  static bool encodeTelemetry(
      const MqttTelemetry& telemetry,
      char* output,
      size_t outputSize);
};

}  // namespace sportsos
