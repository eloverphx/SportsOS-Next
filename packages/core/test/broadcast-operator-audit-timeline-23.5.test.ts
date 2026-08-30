import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.5 operator audit timeline / action history", () => {
  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("merges existing coordinator and go-live audit sources",()=> {
    expect(route).toContain("listBroadcastCoordinatorAudit");
    expect(route).toContain("listGoLiveAuditEvents");
    expect(route).toContain('"COORDINATOR"');
    expect(route).toContain('"GO_LIVE"');
  });

  it("provides operator timeline endpoint",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-timeline"');
  });

  it("sorts combined events by timestamp",()=> {
    expect(route).toContain("Date.parse");
    expect(route).toContain(".sort(");
  });

  it("provides operator timeline UI",()=> {
    expect(page).toContain("Operator Timeline");
    expect(page).toContain("Load Action History");
    expect(page).toContain("timelineEvents");
  });

  it("shows operator and correlation context",()=> {
    expect(page).toContain("Operator:");
    expect(page).toContain("Correlation:");
  });

  it("does not create new audit persistence in dashboard",()=> {
    expect(page).not.toContain("localStorage");
    expect(page).not.toContain("indexedDB");
  });
});
