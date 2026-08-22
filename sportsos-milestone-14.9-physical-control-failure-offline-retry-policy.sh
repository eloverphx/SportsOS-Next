#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.9-physical-control-failure-offline-retry-policy"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardControlInputClient.h" \
  "$ROOT/firmware/esp32-scoreboard/src/ScoreboardControlInputClient.cpp" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp" \
  "$ROOT/firmware/esp32-scoreboard/build-in-docker.sh"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

QUEUE_H="firmware/esp32-scoreboard/include/ScoreboardControlRetryQueue.h"
QUEUE_CPP="firmware/esp32-scoreboard/src/ScoreboardControlRetryQueue.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/physical-control-failure-offline-retry-policy-14.9.test.ts"

for file in "$QUEUE_H" "$QUEUE_CPP" "$MAIN" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$QUEUE_H")" \
  "$(dirname "$QUEUE_CPP")" \
  "$(dirname "$TEST")"

cat > "$QUEUE_H" <<'EOF'
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
EOF

cat > "$QUEUE_CPP" <<'EOF'
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

const includeLine =
  '#include "ScoreboardControlRetryQueue.h"';

if (!text.includes(includeLine)) {
  const includes =
    [...text.matchAll(/^#include .*$/gm)];

  if (includes.length === 0) {
    throw new Error(
      "Unable to locate include block in main.cpp.",
    );
  }

  const last =
    includes[includes.length - 1];

  const insertAt =
    last.index +
    last[0].length;

  text =
    text.slice(0, insertAt) +
    "\n" +
    includeLine +
    text.slice(insertAt);
}

for (const line of [
  "using sportsos::ScoreboardControlRetryQueue;",
]) {
  if (text.includes(line)) {
    continue;
  }

  const matches =
    [...text.matchAll(/^using sportsos::.*?;$/gm)];

  if (matches.length === 0) {
    throw new Error(
      `Unable to add using declaration: ${line}`,
    );
  }

  const last =
    matches[matches.length - 1];

  const insertAt =
    last.index +
    last[0].length;

  text =
    text.slice(0, insertAt) +
    "\n" +
    line +
    text.slice(insertAt);
}

if (
  !text.includes(
    "ScoreboardControlRetryQueue scoreboardControlRetryQueue;",
  )
) {
  const anchor =
    "ScoreboardControlInputClient* scoreboardControlInputClient";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate scoreboardControlInputClient global.",
    );
  }

  text =
    text.slice(0, idx) +
    "ScoreboardControlRetryQueue scoreboardControlRetryQueue;\n\n" +
    text.slice(idx);
}

const callbackStart =
  text.indexOf(
    "void onScoreboardButtonEvent(",
  );

if (callbackStart === -1) {
  throw new Error(
    "Unable to locate onScoreboardButtonEvent().",
  );
}

const callbackOpen =
  text.indexOf(
    "{",
    callbackStart,
  );

let depth = 0;
let callbackEnd = -1;

for (
  let i = callbackOpen;
  i < text.length;
  i += 1
) {
  if (text[i] === "{") {
    depth += 1;
  } else if (text[i] === "}") {
    depth -= 1;

    if (depth === 0) {
      callbackEnd = i + 1;
      break;
    }
  }
}

if (callbackEnd === -1) {
  throw new Error(
    "Unable to locate button callback end.",
  );
}

let callback =
  text.slice(
    callbackStart,
    callbackEnd,
  );

const submitSnippet =
`    const auto submitResult =
        scoreboardControlInputClient->submit(
            event.type,
            scoreboardControlSequence,
            event.occurredAtMs);`;

if (
  callback.includes(submitSnippet) &&
  !callback.includes(
    "scoreboardControlRetryQueue.enqueue",
  )
) {
  callback =
    callback.replace(
      submitSnippet,
`${submitSnippet}

    if (
        submitResult ==
          ScoreboardControlSubmitResult::TransportError ||
        submitResult ==
          ScoreboardControlSubmitResult::InvalidResponse
    ) {
      const bool queued =
          scoreboardControlRetryQueue.enqueue(
              event.type,
              scoreboardControlSequence,
              event.occurredAtMs,
              millis());

      Serial.print(
          "[CONTROL] queued=");

      Serial.println(
          queued
            ? "yes"
            : "queue-full");
    }`,
    );
}

text =
  text.slice(0, callbackStart) +
  callback +
  text.slice(callbackEnd);

if (
  !text.includes(
    "scoreboardControlRetryQueue.process(",
  )
) {
  const loopStart =
    text.indexOf(
      "void loop()",
    );

  if (loopStart === -1) {
    throw new Error(
      "Unable to locate loop().",
    );
  }

  const brace =
    text.indexOf(
      "{",
      loopStart,
    );

  if (brace === -1) {
    throw new Error(
      "Unable to locate loop opening brace.",
    );
  }

  text =
    text.slice(0, brace + 1) +
    `
  if (
      scoreboardControlInputClient != nullptr
  ) {
    scoreboardControlRetryQueue.process(
        *scoreboardControlInputClient,
        millis());
  }
` +
    text.slice(brace + 1);
}

fs.writeFileSync(file, text);
NODE

cat >> "$README" <<'EOF'

## Milestone 14.9 — Physical control failure / offline retry policy

Physical control transport now includes a bounded firmware retry queue for temporary network/API failures.

Behavior:

- initial physical button press still receives one unique sequence number
- temporary transport failures are queued
- retries reuse the **same sequence number**
- server duplicate protection makes replay idempotent
- `ACCEPTED`, `REJECTED`, and `IGNORED_DUPLICATE` are terminal results
- transport errors and malformed responses are retryable
- queue capacity is 16 pending controls
- maximum attempts per control is 5
- retry delay uses bounded exponential backoff
- exhausted entries are dropped with a serial diagnostic

The retry queue does not invent new control events and does not mutate game state locally.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.9 physical control failure / offline retry policy", () => {
  const header = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/include/ScoreboardControlRetryQueue.h",
      import.meta.url,
    ),
    "utf8",
  );

  const source = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/ScoreboardControlRetryQueue.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("uses a bounded retry queue", () => {
    expect(header).toContain(
      "CAPACITY = 16",
    );

    expect(header).toContain(
      "MAX_ATTEMPTS = 5",
    );
  });

  it("reuses the original sequence number", () => {
    expect(source).toContain(
      "entry.sequence",
    );

    expect(source).toContain(
      "entry.occurredAtMs",
    );
  });

  it("treats accepted rejected and duplicate as terminal", () => {
    expect(source).toContain(
      "ScoreboardControlSubmitResult::Accepted",
    );

    expect(source).toContain(
      "ScoreboardControlSubmitResult::Rejected",
    );

    expect(source).toContain(
      "ScoreboardControlSubmitResult::IgnoredDuplicate",
    );
  });

  it("uses bounded exponential backoff", () => {
    expect(source).toContain(
      "BASE_RETRY_MS",
    );

    expect(source).toContain(
      "1UL << bounded",
    );
  });

  it("queues only retryable submit failures", () => {
    expect(main).toContain(
      "ScoreboardControlSubmitResult::TransportError",
    );

    expect(main).toContain(
      "ScoreboardControlSubmitResult::InvalidResponse",
    );

    expect(main).toContain(
      "scoreboardControlRetryQueue.enqueue",
    );
  });

  it("processes retry queue from firmware loop", () => {
    expect(main).toContain(
      "scoreboardControlRetryQueue.process",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - bounded ESP32 physical-control retry queue"
echo "  - 16-entry capacity"
echo "  - max 5 attempts"
echo "  - bounded exponential retry backoff"
echo "  - same sequence number reused across retries"
echo "  - ACCEPTED / REJECTED / DUPLICATE terminal handling"
echo "  - retry only on transport/invalid-response failures"
echo "  - queue-full / retry-exhausted diagnostics"
echo "  - Milestone 14.9 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Then runtime gate:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 14.10 - Physical Control Acceptance / Closeout"
