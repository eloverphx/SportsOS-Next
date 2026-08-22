#include "ScoreboardHardwareProfile.h"

namespace sportsos {

ScoreboardHardwareProfile
ScoreboardHardwareProfiles::minimalBench() {
  return {
      "minimal-bench",
      "Minimal Bench Test",
      {
          NumericDisplayBackend::GenericMultiplexed,
          2,
          2,
          1,
          2,
          2,
          false,
          true,
      },
      false,
      true,
  };
}

ScoreboardHardwareProfile
ScoreboardHardwareProfiles::standardHockey() {
  return {
      "standard-hockey",
      "Standard Hockey Scoreboard",
      {
          NumericDisplayBackend::GenericMultiplexed,
          2,
          2,
          1,
          2,
          2,
          false,
          true,
      },
      true,
      true,
  };
}

bool ScoreboardHardwareProfiles::validate(
    const ScoreboardHardwareProfile& profile) {
  if (
      profile.id == nullptr ||
      profile.id[0] == '\0' ||
      profile.displayName == nullptr ||
      profile.displayName[0] == '\0'
  ) {
    return false;
  }

  const NumericDisplayProfile& display =
      profile.numericDisplay;

  if (
      display.backend ==
      NumericDisplayBackend::None
  ) {
    return false;
  }

  if (
      display.homeScoreDigits == 0 ||
      display.awayScoreDigits == 0 ||
      display.periodDigits == 0 ||
      display.clockMinuteDigits == 0 ||
      display.clockSecondDigits == 0
  ) {
    return false;
  }

  return true;
}

}  // namespace sportsos
