#include "ScoreboardDisplayController.h"

namespace sportsos {

ScoreboardDisplayController::ScoreboardDisplayController(
    ScoreboardDisplayDriver& driver)
    : driver_(driver) {}

bool ScoreboardDisplayController::begin() {
  return driver_.begin();
}

void ScoreboardDisplayController::update(
    const ScoreboardState& state,
    ConnectivityHealth connectivityHealth) {
  DisplayFrame frame{};

  frame.homeScore =
      state.homeScore;

  frame.awayScore =
      state.awayScore;

  frame.hasPeriod =
      state.hasPeriod;

  frame.period =
      state.period;

  frame.remainingMs =
      state.clock.remainingMs;

  frame.clockRunning =
      state.clock.running;

  frame.hornActive =
      state.hornActive;

  frame.hasGame =
      state.hasGame;

  frame.health =
      mapHealth(
          connectivityHealth);

  driver_.render(
      frame);

  driver_.setHorn(
      state.hornActive);

  driver_.setStatusIndicator(
      frame.health);
}

DisplayHealthState
ScoreboardDisplayController::mapHealth(
    ConnectivityHealth connectivityHealth) {
  switch (connectivityHealth) {
    case ConnectivityHealth::Healthy:
      return DisplayHealthState::Normal;

    case ConnectivityHealth::WifiLost:
      return DisplayHealthState::WifiLost;

    case ConnectivityHealth::MqttLost:
      return DisplayHealthState::MqttLost;

    case ConnectivityHealth::StaleAuthoritativeState:
      return DisplayHealthState::Stale;

    case ConnectivityHealth::RecoveryRequired:
      return DisplayHealthState::RecoveryRequired;

    default:
      return DisplayHealthState::RecoveryRequired;
  }
}

}  // namespace sportsos
