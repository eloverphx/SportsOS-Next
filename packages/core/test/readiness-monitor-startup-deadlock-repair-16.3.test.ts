import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.3 readiness monitor startup deadlock repair", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const app = fs.readFileSync(
    new URL(
      "../../../apps/api/src/app.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("does not run app.inject synchronously during buildApp construction", () => {
    const startup =
      monitor.slice(
        monitor.indexOf(
          "export function startScoreboardReadinessIncidentMonitor",
        ),
      );

    expect(startup).toContain(
      "setTimeout",
    );

    expect(startup).toContain(
      "initialRun.unref",
    );

    expect(startup).not.toContain(
      "\n  run();\n",
    );
  });

  it("retains recurring readiness monitoring", () => {
    expect(monitor).toContain(
      "setInterval",
    );

    expect(monitor).toContain(
      "SPORTSOS_READINESS_MONITOR_INTERVAL_MS",
    );
  });

  it("stops the monitor when Fastify closes", () => {
    expect(app).toContain(
      "stopScoreboardReadinessIncidentMonitor",
    );

    expect(app).toContain(
      '"onClose"',
    );
  });
});
