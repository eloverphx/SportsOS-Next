import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.10 deployment / release readiness acceptance", () => {
  const readiness =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastReleaseReadiness.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const secrets =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/secretEnvironmentValidation.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const smoke =
    fs.readFileSync(
      new URL(
        "../../../scripts/release-smoke-test.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const rollback =
    fs.readFileSync(
      new URL(
        "../../../scripts/release-rollback-preflight.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const artifact =
    fs.readFileSync(
      new URL(
        "../../../scripts/generate-release-artifact.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const rehearsal =
    fs.readFileSync(
      new URL(
        "../../../scripts/staging-production-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const dashboard =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/deployment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains runtime release readiness",()=> {
    expect(readiness).toContain("runtime:node-env");
    expect(readiness).toContain("runtime:data-dir");
    expect(readiness).toContain("runtime:dashboard-origin");
    expect(readiness).toContain("runtime:public-api-url");
  });

  it("retains strict production secret quality gates",()=> {
    expect(secrets).toContain("jwt:quality");
    expect(secrets).toContain("mysql-password:quality");
    expect(secrets).toContain("minio-password:quality");
  });

  it("retains release smoke test",()=> {
    expect(smoke).toContain("API /health");
    expect(smoke).toContain("Dashboard reachable");
    expect(smoke).toContain("Release readiness");
    expect(smoke).toContain("Data migration readiness");
  });

  it("retains rollback and restore preflight",()=> {
    expect(rollback).toContain("git rev-parse --verify HEAD");
    expect(rollback).toContain("Backup directory writable");
    expect(rollback).toContain("does not perform a rollback");
  });

  it("retains release artifact generation",()=> {
    expect(artifact).toContain("SportsOS Release Artifact");
    expect(artifact).toContain("git log -15");
  });

  it("retains deployment preflight dashboard",()=> {
    expect(dashboard).toContain("Deployment Preflight");
    expect(dashboard).toContain("Deployment Gate");
    expect(dashboard).toContain("READY");
    expect(dashboard).toContain("BLOCKED");
  });

  it("retains full staging-to-production rehearsal",()=> {
    expect(rehearsal).toContain("npm run typecheck && npm test");
    expect(rehearsal).toContain("docker compose up -d --build api dashboard");
    expect(rehearsal).toContain("release-smoke-test.sh");
    expect(rehearsal).toContain("npm run test:e2e:docker");
    expect(rehearsal).toContain("generate-release-artifact.sh");
  });

  it("does not regress into login-shell cwd bug",()=> {
    expect(rehearsal).not.toContain("bash -lc");
    expect(rehearsal).toContain("bash -c");
  });

  it("keeps staging-only secret override narrowly scoped",()=> {
    expect(rehearsal).toContain("SPORTSOS_ALLOW_SECRET_GATE_FAILURE");
    expect(rehearsal).toContain("jwt:quality");
    expect(rehearsal).toContain("mysql-password:quality");
    expect(rehearsal).toContain("minio-password:quality");
  });
});
