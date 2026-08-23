import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 20.10 streaming operations acceptance", () => {
  const acceptance = fs.readFileSync(
    new URL(
      "../../../docs/STREAMING-OPERATIONS-ACCEPTANCE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const destination = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/streamDestinationProfile.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const runtime = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/encoderRuntime.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/encoderRuntimeAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const preflight = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/streamingReadinessPreflight.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("documents the non-authoritative streaming boundary", () => {
    expect(acceptance).toContain("must never become authoritative");
    expect(acceptance).toContain("Authoritative game state");
  });

  it("retains protected destination credentials", () => {
    expect(destination).toContain("credentialRef");
    expect(acceptance).toContain("must never be returned by the API");
  });

  it("retains FFmpeg runtime and telemetry", () => {
    expect(runtime).toContain("spawn(");
    expect(runtime).toContain("getEncoderTelemetry");
    expect(runtime).toContain("scheduleEncoderRestart");
  });

  it("retains runtime audit history", () => {
    expect(audit).toContain("START_REQUESTED");
    expect(audit).toContain("RESTART_EXHAUSTED");
  });

  it("retains authoritative streaming start preflight", () => {
    expect(preflight).toContain("evaluateStreamingReadiness");
    expect(preflight).toContain("SOURCE_CONFIGURATION");
  });

  it("retains operator readiness, telemetry, recovery, and history UX", () => {
    expect(panel).toContain("Streaming Readiness");
    expect(panel).toContain("Publish Health");
    expect(panel).toContain("Recovery State");
    expect(panel).toContain("Encoder Runtime History");
  });

  it("documents final validation gates", () => {
    expect(acceptance).toContain("npm run typecheck && npm test");
    expect(acceptance).toContain("npm run test:e2e:docker");
  });
});
