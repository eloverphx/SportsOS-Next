import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.10 production resilience acceptance", () => {
  const policy=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRecoveryPolicy.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const heartbeat=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRuntimeHeartbeat.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const supervisor=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastResilienceSupervisor.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const controlled=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastControlledRecovery.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const snapshot=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRecoverySnapshotStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const destination=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationFailurePolicy.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const budget=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastResilienceRetryBudget.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const focus=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains fail-safe recovery policy",()=> {
    expect(policy).toContain("require-operator-review");
    expect(policy).toContain("request-controlled-stop");
    expect(policy).toContain("request-controlled-start");
    expect(policy).toContain("startup-grace-period");
  });

  it("retains stale/missing heartbeat detection",()=> {
    expect(heartbeat).toContain('"STALE"');
    expect(heartbeat).toContain('"MISSING"');
    expect(heartbeat).toContain('"UNKNOWN"');
  });

  it("retains heartbeat + recovery supervisor composition",()=> {
    expect(supervisor).toContain("evaluateBroadcastRuntimeHeartbeat");
    expect(supervisor).toContain("evaluateBroadcastRecovery");
  });

  it("keeps recovery operator-controlled",()=> {
    expect(controlled).toContain("Operator name is required.");
    expect(controlled).toContain("approveDestructive");
    expect(controlled).toContain("RECOVERY_REFUSED");
  });

  it("does not let controlled recovery directly manipulate encoder runtime",()=> {
    expect(controlled).not.toContain("startEncoderRuntime");
    expect(controlled).not.toContain("stopEncoderRuntime");
  });

  it("retains persistent restart/crash context",()=> {
    expect(snapshot).toContain("SPORTSOS_DATA_DIR");
    expect(snapshot).toContain("broadcast-recovery-snapshots.json");
  });

  it("retains destination failure classification",()=> {
    expect(destination).toContain('"AUTHENTICATION"');
    expect(destination).toContain('"TRANSIENT_NETWORK"');
    expect(destination).toContain('"RATE_LIMITED"');
    expect(destination).toContain('"TIMEOUT"');
  });

  it("retains bounded retry budget and backoff",()=> {
    expect(budget).toContain("DEFAULT_MAX_ATTEMPTS");
    expect(budget).toContain("DEFAULT_BASE_DELAY_MS");
    expect(budget).toContain("DEFAULT_MAX_DELAY_MS");
    expect(budget).toContain("EXHAUSTED");
    expect(budget).toContain("REFUSED");
  });

  it("retains resilience operator visibility",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/resilience-status"');
    expect(focus).toContain("Resilience Telemetry");
    expect(focus).toContain("Controlled Recovery");
  });

  it("retains chaos regression suite",()=> {
    const chaos=
      fs.readFileSync(
        new URL(
          "../../../packages/core/test/broadcast-resilience-chaos-24.9.test.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(chaos).toContain("failure injection / chaos regression tests");
    expect(chaos).toContain("retry budget");
    expect(chaos).toContain("require-operator-review");
  });
});
