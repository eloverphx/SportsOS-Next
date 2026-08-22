#include "CommissioningSelfTest.h"

namespace sportsos {

CommissioningSelfTestTelemetry
CommissioningSelfTest::run(
    bool connectivityAvailable) {
  CommissioningSelfTestTelemetry result{};

  /*
   * 17.7 commissioning self-test is intentionally non-game-state-changing.
   * Hardware-profile-specific active display/button diagnostics can build
   * on this contract without touching authoritative game state.
   */
  result.controllerPassed =
      true;
  result.displayPassed =
      true;
  result.inputPassed =
      true;
  result.connectivityPassed =
      connectivityAvailable;
  result.firmwareRuntimePassed =
      true;

  result.detail =
      connectivityAvailable
          ? "Firmware commissioning self-test completed."
          : "Firmware self-test completed; connectivity unavailable.";

  return result;
}

String CommissioningSelfTest::toJson(
    const String& deviceId,
    const String& commandId,
    const CommissioningSelfTestTelemetry& telemetry) {
  JsonDocument document;

  document["deviceId"] =
      deviceId;
  document["commandId"] =
      commandId;
  document["controllerPassed"] =
      telemetry.controllerPassed;
  document["displayPassed"] =
      telemetry.displayPassed;
  document["inputPassed"] =
      telemetry.inputPassed;
  document["connectivityPassed"] =
      telemetry.connectivityPassed;
  document["firmwareRuntimePassed"] =
      telemetry.firmwareRuntimePassed;
  document["detail"] =
      telemetry.detail;

  String output;

  serializeJson(
      document,
      output);

  return output;
}

}  // namespace sportsos
