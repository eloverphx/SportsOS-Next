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

describe("Milestone 35.3 safe Unraid incident escalation registration", () => {
  it("keeps the dedicated escalation wrapper", () => {
    const wrapper = read(
      "scripts/unraid-user-script-sportsos-incident-escalation.sh",
    );

    expect(wrapper).toContain(
      "SPORTSOS_M35_3_INCIDENT_ESCALATION_WRAPPER",
    );
    expect(wrapper).toContain(
      'exec bash "$RUNNER" incident-escalation',
    );
  });

  it("removes the invalid helper-based registration from the legacy installer", () => {
    const installer = read(
      "scripts/install-unraid-operations-user-scripts.sh",
    );

    expect(installer).not.toContain(
      "SPORTSOS_M35_3_INCIDENT_ESCALATION_SCHEDULE",
    );
    expect(installer).not.toContain("install_user_script");
  });

  it("uses a dedicated idempotent User Scripts entry installer", () => {
    const installer = read(
      "scripts/install-unraid-incident-escalation-user-script.sh",
    );

    expect(installer).toContain(
      "SPORTSOS_M35_3_2_DIRECT_USER_SCRIPT_ENTRY",
    );
    expect(installer).toContain(
      'ENTRY_NAME="SportsOS Incident Escalation"',
    );
    expect(installer).toContain(
      'install -m 0755 "$SOURCE" "$ENTRY_SCRIPT"',
    );
  });

  it("does not mutate plugin-owned scheduling state", () => {
    const installer = read(
      "scripts/install-unraid-incident-escalation-user-script.sh",
    );

    expect(installer).not.toContain("schedule.json");
    expect(installer).not.toContain("customSchedule.cron");
    expect(installer).not.toContain("/etc/cron");
  });

  it("does not inject webhook secrets or recovery authority", () => {
    const wrapper = read(
      "scripts/unraid-user-script-sportsos-incident-escalation.sh",
    );
    const installer = read(
      "scripts/install-unraid-incident-escalation-user-script.sh",
    );

    for (const source of [wrapper, installer]) {
      expect(source).not.toContain(
        "export SPORTSOS_INCIDENT_ESCALATION_WEBHOOK_URL=",
      );
      expect(source).not.toContain("docker compose restart");
      expect(source).not.toContain("SPORTSOS_APPLY_RECOVERY");
    }
  });
});
