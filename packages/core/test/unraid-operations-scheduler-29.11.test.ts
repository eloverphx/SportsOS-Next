import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.11 Unraid operations scheduler", () => {
  const installer = fs.readFileSync(
    "scripts/install-unraid-operations-user-scripts.sh",
    "utf8",
  );

  const observability = fs.readFileSync(
    "scripts/unraid-user-script-sportsos-observability.sh",
    "utf8",
  );

  it("uses the canonical SportsOS root", () => {
    expect(installer).toContain(
      "/mnt/user/appdata/SportsOS-Next",
    );
  });

  it("does not edit cron directly", () => {
    expect(installer).not.toContain("crontab -");
    expect(installer).not.toContain("/etc/cron");
    expect(installer).not.toContain("/etc/crontab");
  });

  it("creates four narrowly scoped User Scripts entries", () => {
    expect(installer).toContain("SportsOS Observability");
    expect(installer).toContain("SportsOS Recovery");
    expect(installer).toContain("SportsOS Daily Operations");
    expect(installer).toContain("SportsOS Weekly Rehearsal");
  });

  it("uses five-minute observability and recovery cadence", () => {
    expect(installer).toContain('="*/5 * * * *"');
  });

  it("routes automation through the production operations runner", () => {
    expect(observability).toContain(
      "run-production-operations.sh observability-refresh",
    );
    expect(observability).toContain(
      "run-production-operations.sh alert",
    );
  });

  it("does not embed production secrets", () => {
    const combined = [
      installer,
      observability,
      fs.readFileSync(
        "scripts/unraid-user-script-sportsos-recovery.sh",
        "utf8",
      ),
      fs.readFileSync(
        "scripts/unraid-user-script-sportsos-daily.sh",
        "utf8",
      ),
      fs.readFileSync(
        "scripts/unraid-user-script-sportsos-weekly.sh",
        "utf8",
      ),
    ].join("\n");

    expect(combined).not.toContain(
      "SPORTSOS_OPERATIONS_STATUS_TOKEN=",
    );
    expect(combined).not.toContain("MYSQL_PASSWORD=");
    expect(combined).not.toContain("WEBHOOK_URL=");
  });
});
