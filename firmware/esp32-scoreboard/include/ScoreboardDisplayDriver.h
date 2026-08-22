#pragma once

#include <stdint.h>

namespace sportsos {

enum class DisplayHealthState : uint8_t {
  Normal = 0,
  WifiLost,
  MqttLost,
  Stale,
  RecoveryRequired,
};

struct DisplayFrame {
  uint16_t homeScore;
  uint16_t awayScore;

  bool hasPeriod;
  uint8_t period;

  uint32_t remainingMs;
  bool clockRunning;

  bool hornActive;
  bool hasGame;

  DisplayHealthState health;
};

class ScoreboardDisplayDriver {
 public:
  virtual ~ScoreboardDisplayDriver() = default;

  virtual bool begin() = 0;

  virtual void render(
      const DisplayFrame& frame) = 0;

  virtual void setHorn(
      bool active) = 0;

  virtual void setStatusIndicator(
      DisplayHealthState health) = 0;

  virtual void clear() = 0;
};

}  // namespace sportsos
