#include "NullScoreboardDisplayDriver.h"

namespace sportsos {

bool NullScoreboardDisplayDriver::begin() {
  return true;
}

void NullScoreboardDisplayDriver::render(
    const DisplayFrame& frame) {
  lastFrame_ = frame;
}

void NullScoreboardDisplayDriver::setHorn(
    bool active) {
  lastFrame_.hornActive = active;
}

void NullScoreboardDisplayDriver::setStatusIndicator(
    DisplayHealthState health) {
  lastFrame_.health = health;
}

void NullScoreboardDisplayDriver::clear() {
  lastFrame_ = DisplayFrame{};
}

const DisplayFrame&
NullScoreboardDisplayDriver::lastFrame() const {
  return lastFrame_;
}

}  // namespace sportsos
