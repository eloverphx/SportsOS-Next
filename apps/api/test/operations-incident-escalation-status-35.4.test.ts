import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);

function read(relative: string): string {
  return readFileSync(path.join(root, relative), "utf8");
}

describe("Milestone 35.4 escalation delivery telemetry", () => {
  it("ships a dedicated escalation telemetry collector", () => {
    const collector = read(
      "scripts/operations-incident-escalation-status.sh",
    );

    expect(collector).toContain(
      "SPORTSOS_M35_4_ESCALATION_STATUS_COLLECTOR",
    );
    expect(collector).toContain("trackedIncidents");
    expect(collector).toContain("recentDeliveryFailureCount");
    expect(collector).toContain("recentEvents");
  });

  it("merges telemetry into the existing operations snapshot", () => {
    const status = read("scripts/operations-status-snapshot.sh");

    expect(status).toContain(
      "SPORTSOS_M35_4_ESCALATION_STATUS_MERGE",
    );
    expect(status).toContain(
      "SPORTSOS_M35_4_1_STATUS_OWNERSHIP",
    );
    expect(status).toContain("fs.chownSync(statusFile, 1000, 1000)");
    expect(status).toContain("status.incidentEscalation = escalation");
    expect(status).toContain('data/operations-status/latest.json');
  });

  it("does not add recovery or container authority", () => {
    const collector = read(
      "scripts/operations-incident-escalation-status.sh",
    );

    expect(collector).not.toContain("docker compose restart");
    expect(collector).not.toContain("SPORTSOS_APPLY_RECOVERY");
    expect(collector).not.toContain("docker stop");
    expect(collector).not.toContain("docker rm");
  });
});
