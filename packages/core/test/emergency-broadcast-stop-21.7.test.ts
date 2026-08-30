import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.7 emergency stop / broadcast kill switch", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const runtime=fs.readFileSync(new URL("../../../apps/api/src/services/encoderRuntime.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("adds emergency-stopped state",()=> {
    expect(service).toContain('"EMERGENCY_STOPPED"');
    expect(service).toContain("emergencyStoppedAt");
    expect(service).toContain("emergencyStopReason");
  });

  it("suppresses encoder recovery",()=> {
    expect(runtime).toContain("suppressEncoderRecovery");
    expect(runtime).toContain('"EXHAUSTED"');
  });

  it("provides emergency-stop API",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/emergency-stop"');
    expect(route).toContain("stopEncoderRuntime");
  });

  it("requires reset before another start",()=> {
    expect(route).toContain("Emergency-stopped go-live session must be reset before start.");
  });

  it("provides operator kill switch",()=> {
    expect(panel).toContain("Emergency Broadcast Stop");
    expect(panel).toContain("Emergency Stop Broadcast");
  });
});
