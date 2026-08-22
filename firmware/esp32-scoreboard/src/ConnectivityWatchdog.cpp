#include "ConnectivityWatchdog.h"

namespace sportsos {

ConnectivityWatchdog::ConnectivityWatchdog(
    const ConnectivityWatchdogConfig& config)
    : config_(config),
      startedAtMs_(0),
      lastAuthoritativeStateMs_(0),
      lastWifiHealthyMs_(0),
      lastMqttHealthyMs_(0),
      health_(ConnectivityHealth::Healthy) {}

void ConnectivityWatchdog::begin(
    unsigned long nowMs) {
  startedAtMs_ = nowMs;
  lastAuthoritativeStateMs_ = nowMs;
  lastWifiHealthyMs_ = nowMs;
  lastMqttHealthyMs_ = nowMs;
  health_ = ConnectivityHealth::Healthy;
}

ConnectivityHealth ConnectivityWatchdog::evaluate(
    unsigned long nowMs,
    bool wifiConnected,
    bool mqttConnected) {
  if (wifiConnected) {
    lastWifiHealthyMs_ = nowMs;
  }

  if (mqttConnected) {
    lastMqttHealthyMs_ = nowMs;
  }

  if (
      !wifiConnected &&
      nowMs - lastWifiHealthyMs_ >=
          config_.recoveryEscalationMs
  ) {
    health_ =
        ConnectivityHealth::RecoveryRequired;
    return health_;
  }

  if (
      !wifiConnected &&
      nowMs - lastWifiHealthyMs_ >=
          config_.wifiFailureGraceMs
  ) {
    health_ =
        ConnectivityHealth::WifiLost;
    return health_;
  }

  if (
      wifiConnected &&
      !mqttConnected &&
      nowMs - lastMqttHealthyMs_ >=
          config_.recoveryEscalationMs
  ) {
    health_ =
        ConnectivityHealth::RecoveryRequired;
    return health_;
  }

  if (
      wifiConnected &&
      !mqttConnected &&
      nowMs - lastMqttHealthyMs_ >=
          config_.mqttFailureGraceMs
  ) {
    health_ =
        ConnectivityHealth::MqttLost;
    return health_;
  }

  if (
      mqttConnected &&
      nowMs - lastAuthoritativeStateMs_ >=
          config_.staleStateMs
  ) {
    health_ =
        ConnectivityHealth::StaleAuthoritativeState;
    return health_;
  }

  health_ = ConnectivityHealth::Healthy;
  return health_;
}

void ConnectivityWatchdog::noteAuthoritativeState(
    unsigned long nowMs) {
  lastAuthoritativeStateMs_ = nowMs;
}

void ConnectivityWatchdog::noteSuccessfulMqttConnect(
    unsigned long nowMs) {
  lastMqttHealthyMs_ = nowMs;
}

void ConnectivityWatchdog::noteSuccessfulWifiConnect(
    unsigned long nowMs) {
  lastWifiHealthyMs_ = nowMs;
}

ConnectivityHealth ConnectivityWatchdog::health() const {
  return health_;
}

bool ConnectivityWatchdog::displayStateIsStale() const {
  return
      health_ ==
      ConnectivityHealth::StaleAuthoritativeState;
}

bool ConnectivityWatchdog::recoveryRequired() const {
  return
      health_ ==
      ConnectivityHealth::RecoveryRequired;
}

}  // namespace sportsos
