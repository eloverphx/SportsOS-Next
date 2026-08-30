import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 18.11 authoritative assignment-bound start gate", () => {
  const routes = fs.readFileSync(
    new URL(
      "../../../apps/api/src/modules/games/routes.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("places the gate before lifecycle mutation", () => {
    const gate =
      routes.indexOf(
        "AUTHORITATIVE_ASSIGNMENT_BOUND_START_GATE_18_11",
      );

    const mutation =
      routes.indexOf(
        "result = await applyGameScoringAction(",
      );

    expect(gate).toBeGreaterThanOrEqual(0);
    expect(mutation).toBeGreaterThan(gate);
  });

  it("passes current assignment to preflight guard", () => {
    expect(routes).toContain(
      `evaluateGameStartPreflight(
          String(id.data),
          assignedDeviceId,`,
    );
  });

  it("binds emergency override to current assignment", () => {
    expect(routes).toContain(
      `getActiveGameStartPreflightOverride(
            String(id.data),
            assignedDeviceId ??`,
    );
  });

  it("keeps readiness enforcement before mutation", () => {
    const readiness =
      routes.indexOf(
        "evaluatePregameReadinessGate({",
      );

    const mutation =
      routes.indexOf(
        "result = await applyGameScoringAction(",
      );

    expect(readiness).toBeGreaterThanOrEqual(0);
    expect(mutation).toBeGreaterThan(readiness);
  });
});
