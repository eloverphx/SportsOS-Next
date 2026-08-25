import { describe, expect, it } from "vitest";
import {
  evaluateBroadcastRecovery,
} from "../../../apps/api/src/services/broadcastRecoveryPolicy";

describe("Milestone 24.1 broadcast recovery policy", () => {
  it("does not restart a missing live runtime automatically", () => {
    expect(
      evaluateBroadcastRecovery({
        coordinatorIntent: "live",
        runtimeState: "idle",
        stateAgeMs: 60_000,
      }),
    ).toEqual({
      action: "request-controlled-start",
      reason: "runtime-missing",
      automatic: false,
      destructive: false,
    });
  });

  it("does not stop an unexpected runtime automatically", () => {
    expect(
      evaluateBroadcastRecovery({
        coordinatorIntent: "stopped",
        runtimeState: "live",
        stateAgeMs: 60_000,
      }),
    ).toEqual({
      action: "request-controlled-stop",
      reason: "unexpected-runtime",
      automatic: false,
      destructive: true,
    });
  });

  it("observes during startup grace instead of flapping state", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "idle",
      stateAgeMs: 5_000,
    });

    expect(result.action).toBe("observe");
    expect(result.automatic).toBe(true);
    expect(result.destructive).toBe(false);
  });

  it("escalates stale transitions to operator review", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "starting",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.reason).toBe("runtime-transition-stale");
    expect(result.automatic).toBe(false);
  });

  it("escalates failed runtime state", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "failed",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.reason).toBe("runtime-failed");
  });

  it("escalates unknown runtime state", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "unknown",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.reason).toBe("runtime-state-unknown");
  });

  it("allows non-destructive reconciliation when stopped runtime is idle", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "stopped",
      runtimeState: "idle",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("reconcile-to-idle");
    expect(result.automatic).toBe(true);
    expect(result.destructive).toBe(false);
  });

  it("rejects invalid state age conservatively", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "idle",
      stateAgeMs: -1,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.automatic).toBe(false);
  });
});
