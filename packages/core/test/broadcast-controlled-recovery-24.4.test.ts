import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.4 controlled recovery workflow", () => {
  const service=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastControlledRecovery.ts",
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

  const audit=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("requires operator identity",()=> {
    expect(service).toContain("Operator name is required.");
  });

  it("requires explicit approval for destructive recovery",()=> {
    expect(service).toContain("approveDestructive");
    expect(service).toContain("Destructive recovery requires explicit operator approval.");
  });

  it("refuses supervisor operator-review state",()=> {
    expect(service).toContain('"require-operator-review"');
    expect(service).toContain("RECOVERY_REFUSED");
  });

  it("does not directly control encoder runtime",()=> {
    expect(service).not.toContain("startEncoderRuntime");
    expect(service).not.toContain("stopEncoderRuntime");
  });

  it("uses existing coordinator control paths",()=> {
    expect(service).toContain("prepareBroadcastSession");
    expect(service).toContain("stopCoordinatedBroadcast");
    expect(service).toContain("reconcileBroadcastCoordinator");
  });

  it("provides controlled recovery API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/recovery/execute"');
    expect(route).toContain("executeControlledBroadcastRecovery");
  });

  it("provides operator-controlled Focus Mode UI",()=> {
    expect(focus).toContain("Controlled Recovery");
    expect(focus).toContain("Execute Controlled Recovery");
    expect(focus).toContain("Approve destructive recovery if recommended");
  });

  it("audits recovery workflow",()=> {
    expect(audit).toContain('"RECOVERY_REQUESTED"');
    expect(audit).toContain('"RECOVERY_EXECUTED"');
    expect(audit).toContain('"RECOVERY_REFUSED"');
  });
});
