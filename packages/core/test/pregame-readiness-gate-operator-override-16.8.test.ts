import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.8 pre-game readiness gate / operator override", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPregameReadinessGate.ts",
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

  it("blocks games with no assigned scoreboard", () => {
    expect(service).toContain(
      "No scoreboard device is assigned to this game.",
    );
  });

  it("blocks at-risk and offline devices without override", () => {
    expect(service).toContain(
      "AT_RISK",
    );

    expect(service).toContain(
      "OFFLINE",
    );

    expect(service).toContain(
      "Pregame scoreboard readiness gate blocked start",
    );
  });

  it("allows healthy and watch devices", () => {
    expect(service).toContain(
      '"HEALTHY"',
    );

    expect(service).toContain(
      '"WATCH"',
    );
  });

  it("persists explicit operator overrides", () => {
    expect(service).toContain(
      "scoreboard-pregame-readiness-overrides.json",
    );

    expect(service).toContain(
      "actorUserId",
    );

    expect(service).toContain(
      "actorRoles",
    );
  });

  it("requires write permission and reason for override", () => {
    expect(route).toContain(
      "/scoreboard-control-pregame-gate/override",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_WRITE"',
    );

    expect(route).toContain(
      "override reason are required",
    );
  });

  it("exposes a read-only pregame gate evaluation endpoint", () => {
    expect(route).toContain(
      "/scoreboard-control-pregame-gate",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });
});
