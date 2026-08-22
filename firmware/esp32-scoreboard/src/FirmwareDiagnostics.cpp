#include "FirmwareDiagnostics.h"

#include <WiFi.h>
#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (
      destination == nullptr ||
      destinationSize == 0
  ) {
    return;
  }

  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }

  strncpy(
      destination,
      source,
      destinationSize - 1);

  destination[
      destinationSize - 1] = '\0';
}

}  // namespace

FirmwareDiagnosticSnapshot
FirmwareDiagnostics::build(
    const ScoreboardState& state,
    ConnectivityHealth health,
    bool wifiConnected,
    bool mqttConnected) {
  FirmwareDiagnosticSnapshot snapshot{};

  snapshot.uptimeSeconds =
      millis() / 1000UL;

  snapshot.wifiRssi =
      wifiConnected
          ? WiFi.RSSI()
          : 0;

  snapshot.freeHeapBytes =
      ESP.getFreeHeap();

  snapshot.wifiConnected =
      wifiConnected;

  snapshot.mqttConnected =
      mqttConnected;

  snapshot.authoritativeStateStale =
      health ==
      ConnectivityHealth::StaleAuthoritativeState;

  snapshot.recoveryRequired =
      health ==
      ConnectivityHealth::RecoveryRequired;

  snapshot.connectionState =
      state.connectionState;

  snapshot.connectivityHealth =
      health;

  copyText(
      snapshot.deviceId,
      sizeof(snapshot.deviceId),
      state.deviceId);

  snapshot.hasGame =
      state.hasGame;

  copyText(
      snapshot.gameId,
      sizeof(snapshot.gameId),
      state.hasGame
          ? state.gameId
          : "");

  return snapshot;
}

const char*
FirmwareDiagnostics::connectionStateText(
    ConnectionState state) {
  switch (state) {
    case ConnectionState::Offline:
      return "OFFLINE";
    case ConnectionState::Connecting:
      return "CONNECTING";
    case ConnectionState::Online:
      return "ONLINE";
    case ConnectionState::Degraded:
      return "DEGRADED";
    default:
      return "UNKNOWN";
  }
}

const char*
FirmwareDiagnostics::connectivityHealthText(
    ConnectivityHealth health) {
  switch (health) {
    case ConnectivityHealth::Healthy:
      return "HEALTHY";
    case ConnectivityHealth::WifiLost:
      return "WIFI_LOST";
    case ConnectivityHealth::MqttLost:
      return "MQTT_LOST";
    case ConnectivityHealth::StaleAuthoritativeState:
      return "STALE_AUTHORITATIVE_STATE";
    case ConnectivityHealth::RecoveryRequired:
      return "RECOVERY_REQUIRED";
    default:
      return "UNKNOWN";
  }
}

}  // namespace sportsos
