#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

namespace sportsos {

struct CommissioningSelfTestCommand {
  String commandId;
  String deviceId;
  String requestedAt;
};

class CommissioningSelfTestCommandCodec {
 public:
  static bool decode(
      const String& payload,
      CommissioningSelfTestCommand& command);
};

}  // namespace sportsos
