import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);

const script = readFileSync(
  path.join(root, "scripts/operations-incident-escalation.sh"),
  "utf8",
);

describe("Milestone 34.8 incident escalation policy", () => {
  it("defines bounded warning and critical escalation thresholds", () => {
    expect(script).toContain(
      'WARNING_ESCALATE_SECONDS="${SPORTSOS_INCIDENT_WARNING_ESCALATE_SECONDS:-1800}"',
    );
    expect(script).toContain(
      'CRITICAL_ESCALATE_SECONDS="${SPORTSOS_INCIDENT_CRITICAL_ESCALATE_SECONDS:-300}"',
    );
    expect(script).toContain(
      'REPEAT_SECONDS="${SPORTSOS_INCIDENT_ESCALATION_REPEAT_SECONDS:-3600}"',
    );
  });

  it("only escalates unresolved warning or critical incidents", () => {
    expect(script).toContain('incident.status !== "resolved"');
    expect(script).toContain(
      '(incident.severity === "warning" || incident.severity === "critical")',
    );
  });

  it("persists dedupe state and an escalation audit trail", () => {
    expect(script).toContain("state.json");
    expect(script).toContain("escalation-events.tsv");
    expect(script).toContain("repeat-cooldown");
    expect(script).toContain("lastEscalatedAt");
  });

  it("supports local-only, webhook, and dry-run delivery", () => {
    expect(script).toContain("SPORTSOS_INCIDENT_ESCALATION_WEBHOOK_URL");
    expect(script).toContain("SPORTSOS_INCIDENT_ESCALATION_DRY_RUN");
    expect(script).toContain('result = "local-only"');
    expect(script).toContain('result = "webhook"');
    expect(script).toContain('result = "dry-run"');
  });

  it("has no recovery or container-control authority", () => {
    expect(script).not.toContain("docker compose restart");
    expect(script).not.toContain("SPORTSOS_APPLY_RECOVERY");
    expect(script).not.toContain("container-recovery-check.sh");
    expect(script).not.toContain("docker stop");
    expect(script).not.toContain("docker rm");
  });

  it("uses a non-overlapping lock and bounded webhook timeout", () => {
    expect(script).toContain("flock -n 9");
    expect(script).toContain('"--max-time",');
    expect(script).toContain('"10",');
  });
});
