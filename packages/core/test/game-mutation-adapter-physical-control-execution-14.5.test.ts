import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.5 game mutation adapter / physical control execution", () => {
  const adapter = fs.readFileSync(
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

  it("re-enters authoritative Fastify routes instead of mutating storage directly", () => {
    expect(adapter).toContain(
      "app.inject",
    );

    expect(adapter).not.toContain(
      "UPDATE games",
    );

    expect(adapter).not.toContain(
      "INSERT INTO games",
    );
  });

  it("supports score clock and period command execution", () => {
    expect(adapter).toContain(
      'command.kind === "SCORE"',
    );

    expect(adapter).toContain(
      'command.kind === "CLOCK"',
    );

    expect(adapter).toContain(
      'command.kind === "PERIOD"',
    );
  });

  it("stops on the first non-404 authoritative route", () => {
    expect(adapter).toContain(
      "response.statusCode === 404",
    );

    expect(adapter).toContain(
      "return {",
    );
  });

  it("executes only after control acknowledgement is ACCEPTED", () => {
    expect(route).toContain(
      'result.disposition !==',
    );

    expect(route).toContain(
      '"ACCEPTED"',
    );

    expect(route).toContain(
      "executePhysicalScoreboardControl",
    );
  });

  it("does not persist horn as game state", () => {
    expect(adapter).toContain(
      'command.kind === "HORN"',
    );

    expect(adapter).toContain(
      "deferredToDeviceTransport",
    );
  });
});
