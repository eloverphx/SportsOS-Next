import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.9 authoritative active broadcast discovery", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastSessionCoordinator.ts",import.meta.url),"utf8");
  const app=fs.readFileSync(new URL("../../../apps/api/src/app.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/broadcastSessionCoordinator.ts",import.meta.url),"utf8");

  it("discovers known coordinator game ids",()=> {
    expect(service).toContain("listKnownBroadcastCoordinatorGameIds");
    expect(service).toContain("store.records");
  });

  it("derives active state from existing operational sources",()=> {
    expect(service).toContain("coordinator.intent");
    expect(service).toContain("getGoLiveSession");
    expect(service).toContain("encoderRuntimeSnapshot");
  });

  it("recognizes active go-live states",()=> {
    for(const state of ["ARMED","STARTING","LIVE","DEGRADED","STOPPING"]) {
      expect(service).toContain(`"${state}"`);
    }
  });

  it("does not create a separate active flag",()=> {
    expect(service).not.toContain("broadcastActive:");
    expect(service).not.toContain("isBroadcastActive:");
  });

  it("wires supervisor runtime to active discovery",()=> {
    expect(app).toContain("listActiveBroadcastGameIds");
    expect(app).toContain("gameIds: () => listActiveBroadcastGameIds()");
    expect(app).not.toContain("gameIds: () => []");
  });

  it("provides active broadcast discovery API",()=> {
    expect(route).toContain('"/broadcast-coordinator/active"');
    expect(route).toContain("listActiveBroadcastGameIds");
  });
});
