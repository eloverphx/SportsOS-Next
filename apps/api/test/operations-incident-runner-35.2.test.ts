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

describe("Milestone 35.2 production runner escalation integration", () => {
  it("adds an explicit incident-escalation runner mode", () => {
    const runner = read("scripts/run-production-operations.sh");

    expect(runner).toContain("SPORTSOS_M35_2_INCIDENT_ESCALATION_RUNNER");
    expect(runner).toContain("run_incident_escalation()");
    expect(runner).toContain("incident-escalation)");
    expect(runner).toContain('bash "$escalation_script" "$ROOT"');
  });

  it("does not silently add escalation to daily or weekly operations", () => {
    const runner = read("scripts/run-production-operations.sh");
    const markerIndex = runner.indexOf(
      "SPORTSOS_M35_2_INCIDENT_ESCALATION_RUNNER",
    );

    expect(markerIndex).toBeGreaterThanOrEqual(0);
    expect(runner).not.toContain(
      "SPORTSOS_M35_2_AUTO_SCHEDULED_ESCALATION",
    );
  });

  it("normalizes escalation state permissions", () => {
    const escalation = read("scripts/operations-incident-escalation.sh");

    expect(escalation).toContain(
      "SPORTSOS_M35_2_ESCALATION_PERMISSION_NORMALIZATION",
    );
    expect(escalation).toContain('chmod 0750 "$STATE_DIR"');
    expect(escalation).toContain('chmod 0640 "$STATE_FILE"');
    expect(escalation).toContain('chmod 0640 "$AUDIT_FILE"');
  });

  it("keeps escalation free of recovery/container authority", () => {
    const escalation = read("scripts/operations-incident-escalation.sh");

    expect(escalation).not.toContain("docker compose restart");
    expect(escalation).not.toContain("SPORTSOS_APPLY_RECOVERY");
    expect(escalation).not.toContain("container-recovery-check.sh");
    expect(escalation).not.toContain("docker stop");
    expect(escalation).not.toContain("docker rm");
  });
});
