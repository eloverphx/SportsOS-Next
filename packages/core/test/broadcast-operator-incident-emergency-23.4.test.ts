import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.4 operator incident / emergency controls", () => {
  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides incident controls for degraded broadcasts",()=> {
    expect(page).toContain("Incident / Emergency Controls");
    expect(page).toContain("Acknowledge Incident");
    expect(page).toContain("Retry Health Check");
    expect(page).toContain('"DEGRADED"');
  });

  it("requires operator identity for acknowledgement",()=> {
    expect(page).toContain("incidentOperator");
    expect(page).toContain("!incidentOperator.trim()");
  });

  it("provides emergency stop control",()=> {
    expect(page).toContain("Emergency Stop Broadcast");
    expect(page).toContain("emergencyReason");
    expect(page).toContain('"emergency-stop"');
  });

  it("routes through existing go-live API",()=> {
    expect(page).toContain("/go-live-sessions/");
    expect(page).toContain('"acknowledge-incident"');
    expect(page).toContain('"retry-health"');
  });

  it("does not implement encoder control directly",()=> {
    expect(page).not.toContain("stopEncoderRuntime");
    expect(page).not.toContain("startEncoderRuntime");
  });

  it("shows emergency-stopped state",()=> {
    expect(page).toContain('"EMERGENCY_STOPPED"');
    expect(page).toContain("Emergency stop is active");
  });
});
