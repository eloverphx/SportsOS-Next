#pragma once

#include <Arduino.h>

#include "ScoreboardDisplayDriver.h"

namespace sportsos {

struct DigitalOutputConfig {
  int8_t pin;
  bool activeHigh;
  bool enabled;
};

struct GpioScoreboardDisplayConfig {
  DigitalOutputConfig horn;
  DigitalOutputConfig statusNormal;
  DigitalOutputConfig statusWifiLost;
  DigitalOutputConfig statusMqttLost;
  DigitalOutputConfig statusStale;
  DigitalOutputConfig statusRecovery;
};

class GpioScoreboardDisplayDriver final
    : public ScoreboardDisplayDriver {
 public:
  explicit GpioScoreboardDisplayDriver(
      const GpioScoreboardDisplayConfig& config);

  bool begin() override;

  void render(
      const DisplayFrame& frame) override;

  void setHorn(
      bool active) override;

  void setStatusIndicator(
      DisplayHealthState health) override;

  void clear() override;

  const DisplayFrame& lastFrame() const;

  static bool validOutputPin(
      int8_t pin);

 private:
  GpioScoreboardDisplayConfig config_;
  DisplayFrame lastFrame_{};

  void configureOutput(
      const DigitalOutputConfig& output);

  void writeOutput(
      const DigitalOutputConfig& output,
      bool active);

  void clearStatusOutputs();
};

}  // namespace sportsos
