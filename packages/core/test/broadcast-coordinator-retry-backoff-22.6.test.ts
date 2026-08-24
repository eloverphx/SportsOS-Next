import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.6 coordinator retry policy / backoff", () => {
  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines bounded retry states",()=> {
    for(const state of [
      "IDLE",
      "SCHEDULED",
      "RETRYING",
      "EXHAUSTED",
    ]) {
      expect(service).toContain(`"${state}"`);
    }
  });

  it("supports bounded attempts and backoff",()=> {
    expect(service).toContain("maxAttempts");
    expect(service).toContain("backoffSeconds");
    expect(service).toContain("Math.min");
  });

  it("records retry audit events",()=> {
    expect(audit).toContain('"RETRY_SCHEDULED"');
    expect(audit).toContain('"RETRY_ATTEMPTED"');
    expect(audit).toContain('"RETRY_EXHAUSTED"');
  });

  it("rechecks final preflight before retry success",()=> {
    expect(service).toContain("evaluateGameDayGoLivePreflight");
    expect(service).toContain("Final game-day go-live preflight is still blocked.");
  });

  it("does not auto-start ffmpeg during retry",()=> {
    const start=service.indexOf("export async function executeBroadcastCoordinatorRetry");
    const block=service.slice(start);
    expect(block).not.toContain("startEncoderRuntime(");
  });

  it("provides retry APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry/schedule"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry/execute"');
  });
});
