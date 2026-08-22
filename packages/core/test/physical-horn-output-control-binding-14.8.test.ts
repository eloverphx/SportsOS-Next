import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.8 physical horn / output control binding", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalHornOutput.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const execution = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlExecution.ts",
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

  it("re-enters existing scoreboard device command routes", () => {
    expect(service).toContain(
      "app.inject",
    );

    expect(service).toContain(
      "/scoreboard-devices/",
    );

    expect(service).toContain(
      "TRIGGER_HORN",
    );
  });

  it("does not write horn state directly", () => {
    expect(service).not.toContain(
      "UPDATE",
    );

    expect(service).not.toContain(
      "INSERT",
    );

    expect(service).not.toContain(
      "mqtt.publish",
    );
  });

  it("resolves horn device from existing assignment API", () => {
    expect(execution).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(execution).toContain(
      "triggerPhysicalHornOutput",
    );
  });

  it("fails safely if there is no assigned device", () => {
    expect(execution).toContain(
      "No scoreboard device assignment is available for horn output.",
    );
  });

  it("skips game-state reconciliation for horn side effects", () => {
    expect(route).toContain(
      'execution.command.kind ===',
    );

    expect(route).toContain(
      '"HORN"',
    );

    expect(route).toContain(
      "reconciliation:",
    );
  });
});
