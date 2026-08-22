#pragma once

#include <Arduino.h>

namespace sportsos {

enum class ConnectivityHealth : uint8_t {
  Healthy = 0,
  WifiLost,
  MqttLost,
  StaleAuthoritativeState,
  RecoveryRequired,
};

struct ConnectivityWatchdogConfig {
  uint32_t wifiFailureGraceMs;
  uint32_t mqttFailureGraceMs;
  uint32_t staleStateMs;
  uint32_t recoveryEscalationMs;
};

class ConnectivityWatchdog {
 public:
  explicit ConnectivityWatchdog(
      const ConnectivityWatchdogConfig& config);

  void begin(
      unsigned long nowMs);

  ConnectivityHealth evaluate(
      unsigned long nowMs,
      bool wifiConnected,
      bool mqttConnected);

  void noteAuthoritativeState(
      unsigned long nowMs);

  void noteSuccessfulMqttConnect(
      unsigned long nowMs);

  void noteSuccessfulWifiConnect(
      unsigned long nowMs);

  ConnectivityHealth health() const;

  bool displayStateIsStale() const;

  bool recoveryRequired() const;

 private:
  ConnectivityWatchdogConfig config_;

  unsigned long startedAtMs_;
  unsigned long lastAuthoritativeStateMs_;
  unsigned long lastWifiHealthyMs_;
  unsigned long lastMqttHealthyMs_;

  ConnectivityHealth health_;
};

}  // namespace sportsos
