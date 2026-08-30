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

describe("Milestone 34.7 dashboard incident operator actions", () => {
  it("keeps the bearer token exclusively in a server action module", () => {
    const actions = read(
      "apps/dashboard/app/dashboard/operations/incidentActions.ts",
    );
    const form = read(
      "apps/dashboard/app/dashboard/operations/IncidentActions.tsx",
    );
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(actions).toContain('"use server"');
    expect(actions).toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(form).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(page).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
  });

  it("calls only the protected acknowledge and resolve endpoints", () => {
    const actions = read(
      "apps/dashboard/app/dashboard/operations/incidentActions.ts",
    );

    expect(actions).toContain(
      'type IncidentAction = "acknowledge" | "resolve"',
    );
    expect(actions).toContain('method: "POST"');
    expect(actions).toContain("Authorization: `Bearer ${token}`");
    expect(actions).toContain('cache: "no-store"');
  });

  it("requires an explicit operator and sends optional notes", () => {
    const actions = read(
      "apps/dashboard/app/dashboard/operations/incidentActions.ts",
    );
    const form = read(
      "apps/dashboard/app/dashboard/operations/IncidentActions.tsx",
    );

    expect(actions).toContain("Operator name is required.");
    expect(actions).toContain(
      "JSON.stringify({ actor, note: note || null })",
    );
    expect(form).toContain("required");
    expect(form).toContain('name="actor"');
  });

  it("does not expose recovery authority or automatic lifecycle actions", () => {
    const actions = read(
      "apps/dashboard/app/dashboard/operations/incidentActions.ts",
    );

    expect(actions).not.toContain("docker");
    expect(actions).not.toContain("SPORTSOS_APPLY_RECOVERY");
    expect(actions).not.toContain("container-recovery-check");
  });

  it("renders actions according to incident lifecycle status", () => {
    const form = read(
      "apps/dashboard/app/dashboard/operations/IncidentActions.tsx",
    );
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(form).toContain('status === "resolved"');
    expect(form).toContain('status === "open"');
    expect(form).toContain("Acknowledge");
    expect(form).toContain("Resolve");

    expect(page).toContain("SPORTSOS_M34_7_DASHBOARD_ACTIONS");
    expect(page).toContain(
      "<IncidentActions incidentId={incident.id} status={incident.status} />",
    );
  });
});
