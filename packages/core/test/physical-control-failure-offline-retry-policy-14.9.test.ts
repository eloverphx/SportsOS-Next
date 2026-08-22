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
