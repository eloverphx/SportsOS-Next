#pragma once

#include <stdint.h>

#include "NumericScoreboardDisplayDriver.h"

namespace sportsos {

struct SegmentBusConfig {
  int8_t dataPin;
  int8_t clockPin;
  int8_t latchPin;
  bool activeHigh;
};

class SegmentDisplayBackend final
    : public NumericScoreboardDisplayDriver {
 public:
  SegmentDisplayBackend(
      const ScoreboardHardwareProfile& profile,
      const SegmentBusConfig& bus);

  bool begin() override;

 protected:
  void writeNumericSnapshot(
      const NumericDisplaySnapshot& snapshot) override;

  void writeHornOutput(
      bool active) override;

  void writeHealthOutput(
      DisplayHealthState health) override;

 private:
  SegmentBusConfig bus_;

  void writeByte(
      uint8_t value);

  static uint8_t encodeDigit(
      uint8_t digit);

  static bool validOutputPin(
      int8_t pin);
};

}  // namespace sportsos
