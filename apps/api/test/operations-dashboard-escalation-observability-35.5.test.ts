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

describe("Milestone 35.5 dashboard escalation observability", () => {
  it("types incident escalation status data", () => {
    const helper = read(
      "apps/dashboard/app/dashboard/operations/operationsStatus.ts",
    );

    expect(helper).toContain(
      "SPORTSOS_M35_5_ESCALATION_STATUS_TYPES",
    );
    expect(helper).toContain("IncidentEscalationStatus");
    expect(helper).toContain(
      "SPORTSOS_M35_5_5_SNAPSHOT_ESCALATION_TYPE",
    );
    expect(helper).toContain(
      "incidentEscalation?: IncidentEscalationStatus",
    );
  });

  it("renders escalation delivery telemetry without a JSX wrapper", () => {
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(page).toContain(
      "SPORTSOS_M35_5_ESCALATION_DASHBOARD",
    );
    expect(page).toContain("Incident Escalation Delivery");
    expect(page).toContain("Recent escalation activity");
    expect(page).toContain("recentDeliveryFailureCount");
    expect(page).toContain("recentEvents");
    expect(page).toContain(
      "SPORTSOS_M35_5_4_RESPONSE_DATA_BINDING",
    );
    expect(page).toContain(
      "response.data?.incidentEscalation",
    );
    expect(page).not.toContain(
      "response.incidentEscalation",
    );
    expect(page).not.toContain(
      "SPORTSOS_M35_5_1_ESCALATION_STATUS_BINDING",
    );
  });

  it("does not render webhook configuration or bearer tokens", () => {
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(page).not.toContain(
      "SPORTSOS_INCIDENT_ESCALATION_WEBHOOK_URL",
    );
    expect(page).not.toContain(
      "SPORTSOS_OPERATIONS_STATUS_TOKEN",
    );
  });
});
