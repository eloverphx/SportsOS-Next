import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.5 preflight assignment binding / device swap invalidation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const guard =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightGuard.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("stores an assignment fingerprint on preflight", () => {
    expect(service).toContain(
      "assignmentFingerprint",
    );

    expect(service).toContain(
      "input.gameId",
    );

    expect(service).toContain(
      "input.deviceId",
    );
  });

  it("compares preflight against the current assignment", () => {
    expect(service).toContain(
      "matchesCurrentAssignment",
    );

    expect(service).toContain(
      "preflight.deviceId ===",
    );
  });

  it("defines an assignment-changed start rejection", () => {
    expect(guard).toContain(
      '"PREFLIGHT_ASSIGNMENT_CHANGED"',
    );

    expect(guard).toContain(
      "scoreboard assignment changed",
    );
  });

  it("requires a new preflight for replacement hardware", () => {
    expect(guard).toContain(
      "matchesCurrentAssignment",
    );

    expect(guard).toContain(
      "currentDeviceId",
    );
  });
});
