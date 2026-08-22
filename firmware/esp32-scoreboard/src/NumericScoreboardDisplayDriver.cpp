#include "NumericScoreboardDisplayDriver.h"

namespace sportsos {

NumericScoreboardDisplayDriver::
NumericScoreboardDisplayDriver(
    const ScoreboardHardwareProfile& profile)
    : profile_(profile),
      hornActive_(false) {}

bool NumericScoreboardDisplayDriver::begin() {
  if (
      !ScoreboardHardwareProfiles::validate(
          profile_)
  ) {
    return false;
  }

  clear();

  return true;
}

void NumericScoreboardDisplayDriver::render(
    const DisplayFrame& frame) {
  snapshot_ =
      buildSnapshot(
          frame);

  writeNumericSnapshot(
      snapshot_);

  setHorn(
      frame.hornActive);

  setStatusIndicator(
      frame.health);
}

void NumericScoreboardDisplayDriver::setHorn(
    bool active) {
  hornActive_ =
      active;

  if (
      !profile_.hornEnabled
  ) {
    writeHornOutput(
        false);
    return;
  }

  writeHornOutput(
      active);
}

void NumericScoreboardDisplayDriver::setStatusIndicator(
    DisplayHealthState health) {
  snapshot_.health =
      health;

  if (
      !profile_.statusIndicatorsEnabled
  ) {
    return;
  }

  writeHealthOutput(
      health);
}

void NumericScoreboardDisplayDriver::clear() {
  snapshot_ =
      NumericDisplaySnapshot{};

  hornActive_ =
      false;

  writeNumericSnapshot(
      snapshot_);

  writeHornOutput(
      false);

  if (
      profile_.statusIndicatorsEnabled
  ) {
    writeHealthOutput(
        DisplayHealthState::Normal);
  }
}

const NumericDisplaySnapshot&
NumericScoreboardDisplayDriver::snapshot() const {
  return snapshot_;
}

bool NumericScoreboardDisplayDriver::hornActive() const {
  return hornActive_;
}

NumericDisplaySnapshot
NumericScoreboardDisplayDriver::buildSnapshot(
    const DisplayFrame& frame) {
  NumericDisplaySnapshot snapshot{};

  snapshot.homeScore =
      frame.homeScore;

  snapshot.awayScore =
      frame.awayScore;

  snapshot.period =
      frame.period;

  snapshot.hasPeriod =
      frame.hasPeriod;

  const uint32_t totalSeconds =
      frame.remainingMs / 1000UL;

  snapshot.clockMinutes =
      static_cast<uint16_t>(
          totalSeconds / 60UL);

  snapshot.clockSeconds =
      static_cast<uint8_t>(
          totalSeconds % 60UL);

  snapshot.clockRunning =
      frame.clockRunning;

  snapshot.health =
      frame.health;

  return snapshot;
}

void NumericScoreboardDisplayDriver::writeNumericSnapshot(
    const NumericDisplaySnapshot&) {
  /*
   * Hardware backend intentionally deferred.
   * Concrete shift-register or multiplexed drivers will override this.
   */
}

void NumericScoreboardDisplayDriver::writeHornOutput(
    bool) {}

void NumericScoreboardDisplayDriver::writeHealthOutput(
    DisplayHealthState) {}

}  // namespace sportsos
