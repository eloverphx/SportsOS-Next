import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.5 health / smoke-test command bundle", () => {
  const smoke =
    fs.readFileSync(
      new URL(
        "../../../scripts/release-smoke-test.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("checks API and dashboard containers",()=> {
    expect(smoke).toContain("sportsos_api");
    expect(smoke).toContain("sportsos_dashboard");
    expect(smoke).toContain("container_healthy");
  });

  it("checks API health and dashboard reachability",()=> {
    expect(smoke).toContain("/health");
    expect(smoke).toContain("Dashboard reachable");
  });

  it("checks release readiness endpoints",()=> {
    expect(smoke).toContain("/broadcast-coordinator/release-readiness");
    expect(smoke).toContain("/broadcast-coordinator/data-migration-readiness");
    expect(smoke).toContain("/broadcast-coordinator/secret-environment-validation");
  });

  it("fails with non-zero exit on any failed check",()=> {
    expect(smoke).toContain("failures=$((failures + 1))");
    expect(smoke).toContain("exit 1");
  });

  it("supports deployment URL overrides",()=> {
    expect(smoke).toContain("SPORTSOS_API_URL");
    expect(smoke).toContain("SPORTSOS_DASHBOARD_URL");
    expect(smoke).toContain("SPORTSOS_ROOT");
  });
});
