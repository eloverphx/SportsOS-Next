#pragma once

#include <Arduino.h>

#include "ScoreboardControlInput.h"

namespace sportsos {

struct ScoreboardControlInputClientConfig {
  const char* apiBaseUrl;
  const char* deviceId;
};

enum class ScoreboardControlSubmitResult : uint8_t {
  Accepted = 0,
  Rejected,
  IgnoredDuplicate,
  TransportError,
  InvalidResponse,
};

class ScoreboardControlInputClient {
 public:
  explicit ScoreboardControlInputClient(
      const ScoreboardControlInputClientConfig& config);

  ScoreboardControlSubmitResult submit(
      ScoreboardControlInputType type,
      uint32_t sequence,
      unsigned long occurredAtMs);

  const String& lastReason() const;
  const String& authoritativeGameId() const;

 private:
  ScoreboardControlInputClientConfig config_;
  String lastReason_;
  String authoritativeGameId_;

  String createInputId(
      uint32_t sequence,
      unsigned long occurredAtMs) const;
};

}  // namespace sportsos
