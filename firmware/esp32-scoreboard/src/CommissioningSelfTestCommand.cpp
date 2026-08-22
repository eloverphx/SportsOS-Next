#include "CommissioningSelfTestCommand.h"

namespace sportsos {

bool CommissioningSelfTestCommandCodec::decode(
    const String& payload,
    CommissioningSelfTestCommand& command) {
  JsonDocument document;

  const DeserializationError error =
      deserializeJson(
          document,
          payload);

  if (error) {
    return false;
  }

  const String type =
      document["type"] |
      "";

  if (
      type !=
      "COMMISSIONING_SELF_TEST"
  ) {
    return false;
  }

  command.commandId =
      String(
          document["commandId"] |
          "");

  command.deviceId =
      String(
          document["deviceId"] |
          "");

  command.requestedAt =
      String(
          document["requestedAt"] |
          "");

  return (
      command.commandId.length() > 0 &&
      command.deviceId.length() > 0);
}

}  // namespace sportsos
