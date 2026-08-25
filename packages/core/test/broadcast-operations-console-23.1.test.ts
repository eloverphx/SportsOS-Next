import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.1 broadcast operations console foundation", () => {
  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides consolidated operations summary API",()=> {
    expect(route).toContain(
      '"/broadcast-coordinator/operations-summary"',
    );

    expect(route).toContain(
      "getBroadcastCoordinatorSnapshot",
    );

    expect(route).toContain(
      "evaluateBroadcastCoordinatorHealth",
    );

    expect(route).toContain(
      "getBroadcastCoordinatorRetry",
    );
  });

  it("provides broadcast operations page",()=> {
    expect(page).toContain(
      "Broadcast Operations",
    );

    expect(page).toContain(
      "/broadcast-coordinator/operations-summary",
    );
  });

  it("shows coordinator, go-live, encoder, health, and retry state",()=> {
    expect(page).toContain(
      "Coordinator",
    );

    expect(page).toContain(
      "Go-Live",
    );

    expect(page).toContain(
      "Encoder",
    );

    expect(page).toContain(
      "Publish Health",
    );

    expect(page).toContain(
      "Retry",
    );
  });

  it("surfaces coordinator issues",()=> {
    expect(page).toContain(
      "Coordinator Issues",
    );

    expect(page).toContain(
      "item.health.issues",
    );
  });

  it("refreshes every five seconds",()=> {
    expect(page).toContain(
      "5000",
    );

    expect(page).toContain(
      "setInterval",
    );
  });
});
