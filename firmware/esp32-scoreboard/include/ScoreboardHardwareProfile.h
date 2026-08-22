#pragma once

#include <stdint.h>

namespace sportsos {

enum class NumericDisplayBackend : uint8_t {
  None = 0,
  ShiftRegister,
  GenericMultiplexed,
};

struct NumericDisplayProfile {
  NumericDisplayBackend backend;

  uint8_t homeScoreDigits;
  uint8_t awayScoreDigits;
  uint8_t periodDigits;
  uint8_t clockMinuteDigits;
  uint8_t clockSecondDigits;

  bool leadingZeroMinutes;
  bool leadingZeroSeconds;
};

struct ScoreboardHardwareProfile {
  const char* id;
  const char* displayName;

  NumericDisplayProfile numericDisplay;

  bool hornEnabled;
  bool statusIndicatorsEnabled;
};

class ScoreboardHardwareProfiles {
 public:
  static ScoreboardHardwareProfile minimalBench();

  static ScoreboardHardwareProfile standardHockey();

  static bool validate(
      const ScoreboardHardwareProfile& profile);
};

}  // namespace sportsos
