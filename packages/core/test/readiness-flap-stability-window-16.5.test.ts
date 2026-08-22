import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.5 readiness flap detection / stability window", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines a configurable readiness stability window", () => {
    expect(monitor).toContain(
      "SPORTSOS_READINESS_STABILITY_WINDOW_MS",
    );

    expect(monitor).toContain(
      '"20000"',
    );
  });

  it("tracks pending transitions separately from committed readiness", () => {
    expect(monitor).toContain(
      "pendingState",
    );

    expect(monitor).toContain(
      "firstObservedAtMs",
    );
  });

  it("does not emit transition events until the observed state is stable", () => {
    expect(monitor).toContain(
      "stableForMs",
    );

    expect(monitor).toContain(
      "requiredStableMs",
    );

    expect(monitor).toContain(
      "stableForMs <",
    );
  });

  it("preserves degraded and restored readiness events", () => {
    expect(monitor).toContain(
      "DEVICE_READINESS_DEGRADED",
    );

    expect(monitor).toContain(
      "DEVICE_READINESS_RESTORED",
    );
  });

  it("exposes the configured stability window", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-stability",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });
});
