import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

function repoFile(path: string): string {
  return readFileSync(resolve(process.cwd(), "../..", path), "utf8");
}

describe("Milestone 32 runtime self-healing release contract", () => {
  it("keeps the recovery engine bounded and dry-run by default", () => {
    const script = repoFile("scripts/container-recovery-check.sh");
    const policy = repoFile("scripts/lib/recovery-policy.sh");
    expect(script).toContain('source "${ROOT}/scripts/lib/recovery-policy.sh"');
    expect(policy).toContain("SPORTSOS_M33_5_SHARED_RECOVERY_POLICY");

    expect(script).toContain("SPORTSOS_M32_5_BOUNDED_SELF_HEALING");
    expect(script).toContain('APPLY_RECOVERY="${SPORTSOS_APPLY_RECOVERY:-0}"');
    expect(policy).toContain("SPORTSOS_RECOVERY_COOLDOWN_SECONDS");
    expect(policy).toContain("SPORTSOS_RECOVERY_BUDGET_WINDOW_SECONDS");
    expect(policy).toContain("SPORTSOS_RECOVERY_MAX_ACTIONS_PER_WINDOW");
    expect(policy).toContain("SPORTSOS_RECOVERY_POST_TIMEOUT_SECONDS");
    expect(script).toContain("flock -n");
    expect(script).toContain("recovery-actions.tsv");
  });

  it("allows bounded recovery only for the intended stateless/control services", () => {
    const script = repoFile("scripts/container-recovery-check.sh");
    const policy = repoFile("scripts/lib/recovery-policy.sh");

    expect(policy).toContain('"api:sportsos_api:auto"');
    expect(policy).toContain('"dashboard:sportsos_dashboard:auto"');
    expect(policy).toContain('"mqtt:sportsos_mqtt:auto"');
    expect(policy).toContain(
      '"scoreboard-simulator:sportsos_scoreboard_simulator:auto"',
    );
  });

  it("keeps stateful services monitor-only", () => {
    const script = repoFile("scripts/container-recovery-check.sh");
    const policy = repoFile("scripts/lib/recovery-policy.sh");

    expect(policy).toContain('"mysql:sportsos_mysql:monitor"');
    expect(policy).toContain('"redis:sportsos_redis:monitor"');
    expect(policy).toContain('"minio:sportsos_minio:monitor"');
  });

  it("activates bounded recovery only in the scheduled Unraid recovery wrapper", () => {
    const wrapper = repoFile(
      "scripts/unraid-user-script-sportsos-recovery.sh",
    );

    expect(wrapper).toContain("SPORTSOS_M32_7_SCHEDULED_SELF_HEALING");
    expect(wrapper).toContain("SPORTSOS_APPLY_RECOVERY=1");
    expect(wrapper).toContain("SPORTSOS_RECOVERY_COOLDOWN_SECONDS");
    expect(wrapper).toContain("SPORTSOS_RECOVERY_MAX_ACTIONS_PER_WINDOW");
    expect(wrapper).toContain("run-production-operations.sh");
  });

  it("packages simulator runtime dependencies from its package manifest", () => {
    const dockerfile = repoFile(
      "apps/scoreboard-simulator/Dockerfile",
    );
    const pkg = JSON.parse(
      repoFile("apps/scoreboard-simulator/package.json"),
    );

    expect(pkg.dependencies?.mqtt).toBeTruthy();
    expect(dockerfile).toContain(
      "COPY apps/scoreboard-simulator/package.json ./package.json",
    );
    expect(dockerfile).toContain("npm install --omit=dev");
  });
});
