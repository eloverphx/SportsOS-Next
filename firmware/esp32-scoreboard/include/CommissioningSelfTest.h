#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

namespace sportsos {

struct CommissioningSelfTestTelemetry {
  bool controllerPassed;
  bool displayPassed;
  bool inputPassed;
  bool connectivityPassed;
  bool firmwareRuntimePassed;
  String detail;
};

class CommissioningSelfTest {
 public:
  static CommissioningSelfTestTelemetry run(
      bool connectivityAvailable);

  static String toJson(
      const String& deviceId,
      const String& commandId,
      const CommissioningSelfTestTelemetry& telemetry);
};

}  // namespace sportsos
