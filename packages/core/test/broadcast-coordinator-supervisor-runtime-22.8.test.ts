import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.8 coordinator supervisor runtime scheduling", () => {
  const runtime=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts",import.meta.url),"utf8");
  const app=fs.readFileSync(new URL("../../../apps/api/src/app.ts",import.meta.url),"utf8");
  const audit=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastCoordinatorAudit.ts",import.meta.url),"utf8");

  it("uses bounded scheduling interval",()=> {
    expect(runtime).toContain("5000");
    expect(runtime).toContain("1000");
    expect(runtime).toContain("60000");
  });

  it("runs the existing bounded supervisor tick",()=> {
    expect(runtime).toContain("runBroadcastCoordinatorSupervisorTick");
  });

  it("isolates per-game failures and supports shutdown",()=> {
    expect(runtime).toContain("catch (error)");
    expect(runtime).toContain("options.onError?.");
    expect(runtime).toContain("clearInterval");
  });

  it("registers API lifecycle startup and shutdown",()=> {
    expect(app).toContain("startBroadcastCoordinatorSupervisor");
    expect(app).toContain("stopBroadcastCoordinatorSupervisor?.()");
  });

  it("records runtime lifecycle audit events",()=> {
    expect(audit).toContain('"SUPERVISOR_STARTED"');
    expect(audit).toContain('"SUPERVISOR_STOPPED"');
    expect(audit).toContain('"SUPERVISOR_TICK_FAILED"');
  });

  it("does not directly start encoder",()=> {
    expect(runtime).not.toContain("startEncoderRuntime");
    expect(runtime).not.toContain("startCoordinatedBroadcast");
  });

  it("uses safe empty discovery until authoritative discovery lands",()=> {
    expect(app).toContain("gameIds: () => []");
  });
});
