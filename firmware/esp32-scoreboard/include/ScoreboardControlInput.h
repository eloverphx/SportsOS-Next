#pragma once

#include <Arduino.h>

namespace sportsos {

constexpr uint8_t
CONTROL_INPUT_PROTOCOL_VERSION = 1;

enum class ScoreboardControlInputType : uint8_t {
  ScoreHomeIncrement = 0,
  ScoreHomeDecrement,
  ScoreAwayIncrement,
  ScoreAwayDecrement,
  ClockToggle,
  ClockStart,
  ClockPause,
  PeriodIncrement,
  PeriodDecrement,
  HornTrigger,
};

struct ScoreboardControlInputEvent {
  char inputId[64];
  char deviceId[64];
  ScoreboardControlInputType type;
  uint32_t sequence;
  unsigned long occurredAtMs;
};

class ScoreboardControlInput {
 public:
  static const char* typeText(
      ScoreboardControlInputType type);

  static bool validate(
      const ScoreboardControlInputEvent& event);
};

}  // namespace sportsos
