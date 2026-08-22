import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.6 physical control result / realtime reconciliation", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlReconciliation.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("reuses automatic scoreboard sync instead of creating another sync path", () => {
    expect(service).toContain(
      "AutomaticGameScoreboardSync",
    );

    expect(service).toContain(
      "automaticSync.invalidate",
    );

    expect(service).not.toContain(
      "new AutomaticGameScoreboardSync",
    );
  });

  it("attempts to read authoritative game state after physical mutation", () => {
    expect(service).toContain(
      'method: "GET"',
    );

    expect(service).toContain(
      "/snapshot",
    );

    expect(service).toContain(
      "/state",
    );
  });

  it("invalidates dedupe cache even without a direct snapshot route", () => {
    const occurrences =
      service.match(
        /automaticSync\.invalidate/g,
      ) ?? [];

    expect(
      occurrences.length,
    ).toBeGreaterThanOrEqual(2);
  });

  it("runs reconciliation only after successful authoritative execution", () => {
    const execution =
      route.indexOf(
        "if (!execution.executed)",
      );

    const reconciliation =
      route.indexOf(
        "reconcilePhysicalControlResult",
      );

    expect(execution).toBeGreaterThan(
      -1,
    );

    expect(reconciliation).toBeGreaterThan(
      execution,
    );
  });

  it("returns reconciliation details with the control acknowledgement", () => {
    expect(route).toContain(
      "reconciliation,",
    );
  });
});
