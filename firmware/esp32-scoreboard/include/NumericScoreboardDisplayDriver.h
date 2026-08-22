#pragma once

#include <stdint.h>

#include "ScoreboardDisplayDriver.h"
#include "ScoreboardHardwareProfile.h"

namespace sportsos {

struct NumericDisplaySnapshot {
  uint16_t homeScore;
  uint16_t awayScore;

  uint8_t period;
  bool hasPeriod;

  uint16_t clockMinutes;
  uint8_t clockSeconds;
  bool clockRunning;

  DisplayHealthState health;
};

class NumericScoreboardDisplayDriver
    : public ScoreboardDisplayDriver {
 public:
  explicit NumericScoreboardDisplayDriver(
      const ScoreboardHardwareProfile& profile);

  bool begin() override;

  void render(
      const DisplayFrame& frame) override;

  void setHorn(
      bool active) override;

  void setStatusIndicator(
      DisplayHealthState health) override;

  void clear() override;

  const NumericDisplaySnapshot&
  snapshot() const;

  bool hornActive() const;

  static NumericDisplaySnapshot
  buildSnapshot(
      const DisplayFrame& frame);

 protected:
  virtual void writeNumericSnapshot(
      const NumericDisplaySnapshot& snapshot);

  virtual void writeHornOutput(
      bool active);

  virtual void writeHealthOutput(
      DisplayHealthState health);

 private:
  ScoreboardHardwareProfile profile_;
  NumericDisplaySnapshot snapshot_{};
  bool hornActive_;
};

}  // namespace sportsos
