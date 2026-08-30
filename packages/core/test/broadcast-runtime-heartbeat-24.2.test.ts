import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateBroadcastRuntimeHeartbeat,
} from "../../../apps/api/src/services/broadcastRuntimeHeartbeat";

describe("Milestone 24.2 runtime heartbeat / stale process detection", () => {
  it("marks fresh runtime activity healthy",()=> {
    const now=100_000;

    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            5_000,
          ).toISOString(),
        nowMs:
          now,
      }).state,
    ).toBe(
      "HEALTHY",
    );
  });

  it("marks old runtime activity stale",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            30_000,
          ).toISOString(),
        nowMs:
          now,
      });

    expect(
      result.state,
    ).toBe(
      "STALE",
    );

    expect(
      result.stale,
    ).toBe(
      true,
    );
  });

  it("distinguishes missing heartbeat from stopped runtime",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          null,
      }).state,
    ).toBe(
      "MISSING",
    );

    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "STOPPED",
        lastActivityAt:
          null,
      }).state,
    ).toBe(
      "STOPPED",
    );
  });

  it("classifies failed runtime",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "ERROR",
        lastActivityAt:
          null,
      }).state,
    ).toBe(
      "FAILED",
    );
  });

  it("rejects invalid timestamps conservatively",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          "not-a-date",
      }).state,
    ).toBe(
      "UNKNOWN",
    );
  });

  it("bounds stale threshold",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date().toISOString(),
        staleAfterMs:
          1,
      }).staleAfterMs,
    ).toBe(
      1_000,
    );

    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date().toISOString(),
        staleAfterMs:
          999_999,
      }).staleAfterMs,
    ).toBe(
      300_000,
    );
  });

  it("provides runtime-heartbeat API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/runtime-heartbeat"',
    );

    expect(route).toContain(
      "evaluateBroadcastRuntimeHeartbeat",
    );
  });
});
