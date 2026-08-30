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

describe("Milestone 34.5 Operations Dashboard incident visibility", () => {
  it("fetches incidents server-side through the protected internal API", () => {
    const helper = read(
      "apps/dashboard/app/dashboard/operations/operationsStatus.ts",
    );

    expect(helper).toContain("SPORTSOS_M34_5_INCIDENT_FETCH");
    expect(helper).toContain("/deployment/operations/incidents");
    expect(helper).toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(helper).toContain('cache: "no-store"');
  });

  it("renders a read-only Production Incidents panel", () => {
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(page).toContain("SPORTSOS_M34_5_INCIDENT_PANEL");
    expect(page).toContain("Production Incidents");
    expect(page).toContain("Observability only.");
    expect(page).toContain("incidentData.incidents.map");
  });

  it("does not expose the protected token from the page component", () => {
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(page).not.toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(page).not.toContain("process.env");
  });

  it("does not add incident mutation behavior to the dashboard", () => {
    const page = read(
      "apps/dashboard/app/dashboard/operations/page.tsx",
    );

    expect(page).not.toContain("incident/acknowledge");
    expect(page).not.toContain("incident/resolve");
    expect(page).not.toContain('method: "POST"');
    expect(page).not.toContain('method: "PATCH"');
    expect(page).not.toContain('method: "DELETE"');
  });
});
