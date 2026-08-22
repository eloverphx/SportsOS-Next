#pragma once

#include <Arduino.h>

#include "ConnectivityWatchdog.h"
#include "ScoreboardProtocol.h"

namespace sportsos {

struct FirmwareDiagnosticSnapshot {
  uint32_t uptimeSeconds;
  int32_t wifiRssi;
  uint32_t freeHeapBytes;

  bool wifiConnected;
  bool mqttConnected;
  bool authoritativeStateStale;
  bool recoveryRequired;

  ConnectionState connectionState;
  ConnectivityHealth connectivityHealth;

  char deviceId[64];
  char gameId[64];
  bool hasGame;
};

class FirmwareDiagnostics {
 public:
  static FirmwareDiagnosticSnapshot build(
      const ScoreboardState& state,
      ConnectivityHealth health,
      bool wifiConnected,
      bool mqttConnected);

  static const char* connectionStateText(
      ConnectionState state);

  static const char* connectivityHealthText(
      ConnectivityHealth health);
};

}  // namespace sportsos
