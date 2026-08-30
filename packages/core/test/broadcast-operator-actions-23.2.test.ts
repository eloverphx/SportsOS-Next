import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.2 operator actions / safe control surface", () => {
  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides safe operator action controls",()=> {
    expect(page).toContain("Safe Operator Actions");
    expect(page).toContain("Prepare");
    expect(page).toContain("Reconcile");
    expect(page).toContain("Execute Retry");
    expect(page).toContain("Stop Broadcast");
  });

  it("routes controls through coordinator API",()=> {
    expect(page).toContain("/broadcast-coordinator/");
    expect(page).toContain('"prepare"');
    expect(page).toContain('"reconcile"');
    expect(page).toContain('"retry/execute"');
    expect(page).toContain('"stop"');
  });

  it("does not call encoder runtime directly",()=> {
    expect(page).not.toContain("startEncoderRuntime");
    expect(page).not.toContain("stopEncoderRuntime");
  });

  it("guards retry execution by scheduled state",()=> {
    expect(page).toContain('item.retry.state !==');
    expect(page).toContain('"SCHEDULED"');
  });

  it("refreshes after successful operator action",()=> {
    expect(page).toContain("await load()");
  });
});
