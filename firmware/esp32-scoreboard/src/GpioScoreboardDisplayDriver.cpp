#include "GpioScoreboardDisplayDriver.h"

namespace sportsos {

GpioScoreboardDisplayDriver::
GpioScoreboardDisplayDriver(
    const GpioScoreboardDisplayConfig& config)
    : config_(config) {}

bool GpioScoreboardDisplayDriver::begin() {
  const DigitalOutputConfig outputs[] = {
      config_.horn,
      config_.statusNormal,
      config_.statusWifiLost,
      config_.statusMqttLost,
      config_.statusStale,
      config_.statusRecovery,
  };

  for (const auto& output : outputs) {
    if (
        output.enabled &&
        !validOutputPin(
            output.pin)
    ) {
      return false;
    }
  }

  for (const auto& output : outputs) {
    configureOutput(
        output);
  }

  clear();

  return true;
}

void GpioScoreboardDisplayDriver::render(
    const DisplayFrame& frame) {
  lastFrame_ = frame;

  setHorn(
      frame.hornActive);

  setStatusIndicator(
      frame.health);
}

void GpioScoreboardDisplayDriver::setHorn(
    bool active) {
  lastFrame_.hornActive =
      active;

  writeOutput(
      config_.horn,
      active);
}

void GpioScoreboardDisplayDriver::setStatusIndicator(
    DisplayHealthState health) {
  lastFrame_.health =
      health;

  clearStatusOutputs();

  switch (health) {
    case DisplayHealthState::Normal:
      writeOutput(
          config_.statusNormal,
          true);
      break;

    case DisplayHealthState::WifiLost:
      writeOutput(
          config_.statusWifiLost,
          true);
      break;

    case DisplayHealthState::MqttLost:
      writeOutput(
          config_.statusMqttLost,
          true);
      break;

    case DisplayHealthState::Stale:
      writeOutput(
          config_.statusStale,
          true);
      break;

    case DisplayHealthState::RecoveryRequired:
    default:
      writeOutput(
          config_.statusRecovery,
          true);
      break;
  }
}

void GpioScoreboardDisplayDriver::clear() {
  lastFrame_ =
      DisplayFrame{};

  writeOutput(
      config_.horn,
      false);

  clearStatusOutputs();
}

const DisplayFrame&
GpioScoreboardDisplayDriver::lastFrame() const {
  return lastFrame_;
}

bool GpioScoreboardDisplayDriver::validOutputPin(
    int8_t pin) {
  return
      pin >= 0 &&
      pin <= 33;
}

void GpioScoreboardDisplayDriver::configureOutput(
    const DigitalOutputConfig& output) {
  if (!output.enabled) {
    return;
  }

  pinMode(
      output.pin,
      OUTPUT);

  writeOutput(
      output,
      false);
}

void GpioScoreboardDisplayDriver::writeOutput(
    const DigitalOutputConfig& output,
    bool active) {
  if (!output.enabled) {
    return;
  }

  const uint8_t level =
      active == output.activeHigh
          ? HIGH
          : LOW;

  digitalWrite(
      output.pin,
      level);
}

void GpioScoreboardDisplayDriver::clearStatusOutputs() {
  writeOutput(
      config_.statusNormal,
      false);

  writeOutput(
      config_.statusWifiLost,
      false);

  writeOutput(
      config_.statusMqttLost,
      false);

  writeOutput(
      config_.statusStale,
      false);

  writeOutput(
      config_.statusRecovery,
      false);
}

}  // namespace sportsos
