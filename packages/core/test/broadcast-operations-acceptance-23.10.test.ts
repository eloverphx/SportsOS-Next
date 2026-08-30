import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.10 broadcast operations acceptance", () => {
  const operations =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const focus =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const notes =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastOperatorNotes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains consolidated broadcast operations visibility",()=> {
    expect(operations).toContain("Broadcast Operations");
    expect(operations).toContain("Operator Attention Queue");
    expect(operations).toContain("Coordinator Issues");
  });

  it("retains guarded operator controls",()=> {
    expect(operations).toContain("Safe Operator Actions");
    expect(operations).toContain("Confirm Start Broadcast");
    expect(operations).toContain("Acknowledge Incident");
    expect(operations).toContain("Emergency Stop Broadcast");
  });

  it("retains focus mode workspace",()=> {
    expect(operations).toContain("Open Focus Mode");
    expect(focus).toContain("Broadcast Focus");
    expect(focus).toContain("Safe Operator Actions");
    expect(focus).toContain("Operator Timeline");
  });

  it("retains shift handoff features",()=> {
    expect(focus).toContain("Shift Handoff Notes");
    expect(focus).toContain("Shift Handoff Snapshot");
    expect(focus).toContain("Generate Handoff Snapshot");
  });

  it("retains operator-facing APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/operations-summary"');
    expect(route).toContain('"/broadcast-coordinator/attention-queue"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-timeline"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-notes"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/handoff-summary"');
  });

  it("keeps notes separate from control state",()=> {
    expect(notes).toContain("broadcast-operator-notes.json");
    expect(notes).not.toContain("startEncoderRuntime");
    expect(notes).not.toContain("stopEncoderRuntime");
    expect(notes).not.toContain("setBroadcastCoordinatorIntent");
  });

  it("does not let dashboard directly control encoder runtime",()=> {
    expect(operations).not.toContain("startEncoderRuntime");
    expect(operations).not.toContain("stopEncoderRuntime");
    expect(focus).not.toContain("startEncoderRuntime");
    expect(focus).not.toContain("stopEncoderRuntime");
  });

  it("keeps five-second operational refresh",()=> {
    expect(operations).toContain("5000");
    expect(focus).toContain("5000");
  });
});
