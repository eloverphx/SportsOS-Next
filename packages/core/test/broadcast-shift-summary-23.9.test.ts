import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.9 operator shift summary / handoff snapshot", () => {
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

  it("provides handoff summary API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/handoff-summary"');
  });

  it("combines current state, notes, and recent events",()=> {
    expect(route).toContain("getBroadcastCoordinatorSnapshot");
    expect(route).toContain("evaluateBroadcastCoordinatorHealth");
    expect(route).toContain("getBroadcastCoordinatorRetry");
    expect(route).toContain("listBroadcastOperatorNotes");
    expect(route).toContain("listBroadcastCoordinatorAudit");
    expect(route).toContain("listGoLiveAuditEvents");
  });

  it("limits handoff context",()=> {
    expect(route).toContain("listBroadcastOperatorNotes");
    expect(route).toContain("5");
    expect(route).toContain(".slice(");
    expect(route).toContain("10");
  });

  it("provides focus-mode snapshot UI",()=> {
    expect(focus).toContain("Shift Handoff Snapshot");
    expect(focus).toContain("Generate Handoff Snapshot");
    expect(focus).toContain("handoffSummary");
  });

  it("shows recent notes and events",()=> {
    expect(focus).toContain("Recent Handoff Notes");
    expect(focus).toContain("Recent Operator / Automation Events");
  });

  it("does not create new persistence",()=> {
    expect(route).not.toContain("handoff-summary.json");
    expect(focus).not.toContain("localStorage");
  });
});
