import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve(__dirname, "../../..");

function read(relativePath: string): string {
  return fs.readFileSync(path.join(ROOT, relativePath), "utf8");
}

describe("Milestone 33 recovery observability", () => {
  const policy = read("scripts/lib/recovery-policy.sh");
  const recoveryEngine = read("scripts/container-recovery-check.sh");
  const snapshot = read("scripts/operations-status-snapshot.sh");
  const helper = read(
    "apps/dashboard/app/dashboard/operations/operationsStatus.ts",
  );
  const page = read(
    "apps/dashboard/app/dashboard/operations/page.tsx",
  );

  it("uses one canonical shared recovery policy", () => {
    expect(policy).toContain("SPORTSOS_M33_5_SHARED_RECOVERY_POLICY");
    expect(recoveryEngine).toContain(
      'source "${ROOT}/scripts/lib/recovery-policy.sh"',
    );
    expect(snapshot).toContain(
      'source "${ROOT}/scripts/lib/recovery-policy.sh"',
    );

    for (const token of [
      "SPORTSOS_RECOVERY_RESTART_DELTA_THRESHOLD",
      "SPORTSOS_RECOVERY_COOLDOWN_SECONDS",
      "SPORTSOS_RECOVERY_BUDGET_WINDOW_SECONDS",
      "SPORTSOS_RECOVERY_MAX_ACTIONS_PER_WINDOW",
      "SPORTSOS_RECOVERY_POST_TIMEOUT_SECONDS",
    ]) {
      expect(policy).toContain(token);
    }
  });

  it("keeps the seven-service recovery policy contract", () => {
    for (const entry of [
      "api:sportsos_api:auto",
      "dashboard:sportsos_dashboard:auto",
      "mysql:sportsos_mysql:monitor",
      "redis:sportsos_redis:monitor",
      "mqtt:sportsos_mqtt:auto",
      "minio:sportsos_minio:monitor",
      "scoreboard-simulator:sportsos_scoreboard_simulator:auto",
    ]) {
      expect(policy).toContain(entry);
    }
  });

  it("keeps recovery dry-run as the default authority mode", () => {
    expect(recoveryEngine).toContain(
      'APPLY_RECOVERY="${SPORTSOS_APPLY_RECOVERY:-0}"',
    );
  });

  it("exposes recovery telemetry in the operations snapshot", () => {
    expect(snapshot).toContain(
      "SPORTSOS_M33_6_5_RECOVERY_GUARDRAIL_ENRICHMENT",
    );

    for (const field of [
      "guardrailState",
      "eligible",
      "blockedReason",
      "successfulActionsInWindow",
      "remainingBudget",
      "cooldownRemainingSeconds",
    ]) {
      expect(snapshot).toContain(field);
    }
  });

  it("supports all operator guardrail states", () => {
    for (const state of [
      "ready",
      "cooldown",
      "budget-exhausted",
      "monitor-only",
    ]) {
      expect(snapshot).toContain(state);
    }

    for (const label of [
      "READY",
      "COOLDOWN",
      "BUDGET EXHAUSTED",
      "MONITOR ONLY",
    ]) {
      expect(page).toContain(label);
    }
  });

  it("keeps the real API response nesting for recovery telemetry", () => {
    expect(page).toContain("response.data?.recovery");
    expect(helper).toContain("OperationsStatusResponse");
  });

  it("keeps recovery telemetry on the dashboard observability path", () => {
    expect(page).toContain("SPORTSOS_M33_6_5_DASHBOARD_GUARDRAILS");
    expect(page).toContain("Recovery Guardrails");
    expect(page).toContain("Observability only");

    expect(page).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(page).not.toContain(
      "process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN",
    );
  });

  it("does not move recovery authority into the dashboard", () => {
    expect(page).not.toContain("docker compose restart");
    expect(page).not.toContain("SPORTSOS_APPLY_RECOVERY=1");
    expect(helper).not.toContain("docker compose restart");
  });
});
