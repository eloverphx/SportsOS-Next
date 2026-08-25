import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.8 preflight deployment dashboard", () => {
  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/deployment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides deployment preflight page",()=> {
    expect(page).toContain("Deployment Preflight");
    expect(page).toContain("Deployment Gate");
  });

  it("loads all readiness surfaces",()=> {
    expect(page).toContain("/broadcast-coordinator/release-readiness");
    expect(page).toContain("/broadcast-coordinator/data-migration-readiness");
    expect(page).toContain("/broadcast-coordinator/secret-environment-validation");
    expect(page).toContain("/broadcast-coordinator/rollback-restore-readiness");
    expect(page).toContain("/broadcast-coordinator/deployment-manifest");
  });

  it("blocks unless every readiness section passes",()=> {
    expect(page).toContain("allReady");
    expect(page).toContain('"BLOCKED"');
    expect(page).toContain('"READY"');
  });

  it("shows deployment manifest identity",()=> {
    expect(page).toContain("Deployment Manifest");
    expect(page).toContain("Root Version");
    expect(page).toContain("Commit");
    expect(page).toContain("Tag");
  });

  it("shows release verification commands",()=> {
    expect(page).toContain("Release Verification");
    expect(page).toContain("release-smoke-test.sh");
    expect(page).toContain("test:e2e:docker");
  });

  it("does not expose write actions",()=> {
    expect(page).not.toContain('method: "POST"');
    expect(page).not.toContain('method: "DELETE"');
  });
});
