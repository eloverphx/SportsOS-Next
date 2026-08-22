#pragma once

#include <Arduino.h>

#include "ScoreboardControlInput.h"
#include "ScoreboardControlInputClient.h"

namespace sportsos {

struct PendingScoreboardControlInput {
  ScoreboardControlInputType type;
  uint32_t sequence;
  unsigned long occurredAtMs;
  uint8_t attempts;
  unsigned long nextAttemptAtMs;
  bool occupied;
};

class ScoreboardControlRetryQueue {
 public:
  static constexpr size_t CAPACITY = 16;
  static constexpr uint8_t MAX_ATTEMPTS = 5;
  static constexpr unsigned long BASE_RETRY_MS = 500;

  ScoreboardControlRetryQueue();

  bool enqueue(
      ScoreboardControlInputType type,
      uint32_t sequence,
      unsigned long occurredAtMs,
      unsigned long nowMs);

  void process(
      ScoreboardControlInputClient& client,
      unsigned long nowMs);

  size_t size() const;

 private:
  PendingScoreboardControlInput entries_[CAPACITY];

  static unsigned long retryDelayMs(
      uint8_t attempts);

  void removeAt(
      size_t index);
};

}  // namespace sportsos
