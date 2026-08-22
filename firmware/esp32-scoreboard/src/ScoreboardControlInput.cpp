#include "ScoreboardControlInput.h"

namespace sportsos {

const char*
ScoreboardControlInput::typeText(
    ScoreboardControlInputType type) {
  switch (type) {
    case ScoreboardControlInputType::ScoreHomeIncrement:
      return "SCORE_HOME_INCREMENT";
    case ScoreboardControlInputType::ScoreHomeDecrement:
      return "SCORE_HOME_DECREMENT";
    case ScoreboardControlInputType::ScoreAwayIncrement:
      return "SCORE_AWAY_INCREMENT";
    case ScoreboardControlInputType::ScoreAwayDecrement:
      return "SCORE_AWAY_DECREMENT";
    case ScoreboardControlInputType::ClockToggle:
      return "CLOCK_TOGGLE";
    case ScoreboardControlInputType::ClockStart:
      return "CLOCK_START";
    case ScoreboardControlInputType::ClockPause:
      return "CLOCK_PAUSE";
    case ScoreboardControlInputType::PeriodIncrement:
      return "PERIOD_INCREMENT";
    case ScoreboardControlInputType::PeriodDecrement:
      return "PERIOD_DECREMENT";
    case ScoreboardControlInputType::HornTrigger:
      return "HORN_TRIGGER";
    default:
      return "UNKNOWN";
  }
}

bool ScoreboardControlInput::validate(
    const ScoreboardControlInputEvent& event) {
  return
      event.inputId[0] != '\0' &&
      event.deviceId[0] != '\0' &&
      event.sequence > 0;
}

}  // namespace sportsos
