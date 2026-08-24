import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 22.1 broadcast session coordinator foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const app =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists only coordinator intent, not duplicate runtime state", () => {
    expect(service).toContain(
      "broadcast-session-coordinator.json",
    );

    expect(service).toContain(
      "BroadcastCoordinatorIntent",
    );

    expect(service).toContain(
      "getGoLiveSession",
    );

    expect(service).toContain(
      "encoderRuntimeSnapshot",
    );
  });

  it("composes existing final preflight", () => {
    expect(service).toContain(
      "evaluateGameDayGoLivePreflight",
    );

    expect(service).toContain(
      "prepareBroadcastSession",
    );
  });

  it("blocks preparation when final preflight fails", () => {
    expect(route).toContain(
      "Broadcast preparation is blocked by final go-live preflight.",
    );
  });

  it("provides snapshot, prepare, and reset endpoints", () => {
    expect(route).toContain(
      '"/broadcast-coordinator/:gameId"',
    );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/prepare"',
    );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/reset"',
    );
  });

  it("registers coordinator routes", () => {
    expect(app).toContain(
      "registerBroadcastSessionCoordinatorRoutes",
    );
  });

  it("uses correlation ids for coordination tracing", () => {
    expect(service).toContain(
      "correlationId",
    );

    expect(service).toContain(
      "createCorrelationId",
    );
  });
});
