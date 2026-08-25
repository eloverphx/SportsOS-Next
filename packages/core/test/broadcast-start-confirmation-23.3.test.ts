import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.3 start broadcast confirmation / guarded operator flow", () => {
  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides two-step start confirmation",()=> {
    expect(page).toContain("Start Broadcast");
    expect(page).toContain("Confirm Start Broadcast");
    expect(page).toContain("Cancel Start");
    expect(page).toContain("pendingStartGameId");
  });

  it("requires healthy coordinator",()=> {
    expect(page).toContain("!item.health.healthy");
  });

  it("requires PREPARE intent",()=> {
    expect(page).toContain('item.snapshot.coordinator.intent !==');
    expect(page).toContain('"PREPARE"');
  });

  it("routes confirmed start through coordinator API",()=> {
    expect(page).toContain('"start"');
    expect(page).toContain("runAction");
    expect(page).toContain("/broadcast-coordinator/");
  });

  it("does not directly start encoder",()=> {
    expect(page).not.toContain("startEncoderRuntime");
  });
});
