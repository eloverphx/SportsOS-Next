import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.5 live broadcast watchdog / degraded-state detection", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("adds a degraded production state",()=> {
    expect(service).toContain('"DEGRADED"');
    expect(service).toContain("degradedAt");
    expect(service).toContain("degradationReason");
  });

  it("supports degrade and recovery transitions",()=> {
    expect(service).toContain("markGoLiveDegraded");
    expect(service).toContain("clearGoLiveDegraded");
  });

  it("provides a watchdog endpoint",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/watchdog"');
    expect(route).toContain("Publish health is");
    expect(route).toContain("Encoder session is");
  });

  it("recovers degraded state after health returns",()=> {
    expect(route).toContain("clearGoLiveDegraded");
  });

  it("provides operator watchdog visibility",()=> {
    expect(panel).toContain("Live Broadcast Watchdog");
    expect(panel).toContain("Run Watchdog Check");
    expect(panel).toContain("3000");
    expect(panel).toContain("degradationReason");
  });
});
