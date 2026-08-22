#include "ScoreboardControlRetryQueue.h"

namespace sportsos {

ScoreboardControlRetryQueue::ScoreboardControlRetryQueue()
    : entries_{} {}

bool ScoreboardControlRetryQueue::enqueue(
    ScoreboardControlInputType type,
    uint32_t sequence,
    unsigned long occurredAtMs,
    unsigned long nowMs) {
  for (
      size_t index = 0;
      index < CAPACITY;
      ++index
  ) {
    if (
        entries_[index].occupied &&
        entries_[index].sequence ==
            sequence
    ) {
      return true;
    }
  }

  for (
      size_t index = 0;
      index < CAPACITY;
      ++index
  ) {
    if (
        entries_[index].occupied
    ) {
      continue;
    }

    entries_[index] = {
        type,
        sequence,
        occurredAtMs,
        0,
        nowMs,
        true,
    };

    return true;
  }

  return false;
}

void ScoreboardControlRetryQueue::process(
    ScoreboardControlInputClient& client,
    unsigned long nowMs) {
  for (
      size_t index = 0;
      index < CAPACITY;
      ++index
  ) {
    auto& entry =
        entries_[index];

    if (
        !entry.occupied ||
        nowMs <
            entry.nextAttemptAtMs
    ) {
      continue;
    }

    const auto result =
        client.submit(
            entry.type,
            entry.sequence,
            entry.occurredAtMs);

    if (
        result ==
            ScoreboardControlSubmitResult::Accepted ||
        result ==
            ScoreboardControlSubmitResult::IgnoredDuplicate ||
        result ==
            ScoreboardControlSubmitResult::Rejected
    ) {
      removeAt(index);
      continue;
    }

    entry.attempts += 1;

    if (
        entry.attempts >=
        MAX_ATTEMPTS
    ) {
      Serial.print(
          "[CONTROL] retry exhausted sequence=");

      Serial.println(
          entry.sequence);

      removeAt(index);
      continue;
    }

    entry.nextAttemptAtMs =
        nowMs +
        retryDelayMs(
            entry.attempts);
  }
}

size_t
ScoreboardControlRetryQueue::size() const {
  size_t count = 0;

  for (
      const auto& entry :
      entries_
  ) {
    if (entry.occupied) {
      count += 1;
    }
  }

  return count;
}

unsigned long
ScoreboardControlRetryQueue::retryDelayMs(
    uint8_t attempts) {
  const uint8_t bounded =
      attempts > 4
        ? 4
        : attempts;

  return
      BASE_RETRY_MS *
      (1UL << bounded);
}

void ScoreboardControlRetryQueue::removeAt(
    size_t index) {
  entries_[index] = {
      ScoreboardControlInputType::HornTrigger,
      0,
      0,
      0,
      0,
      false,
  };
}

}  // namespace sportsos
