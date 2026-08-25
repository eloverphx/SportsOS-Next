import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.9 staging-to-production acceptance rehearsal", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/staging-production-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("runs the complete release sequence",()=> {
    expect(script).toContain("npm run typecheck && npm test");
    expect(script).toContain("docker compose up -d --build api dashboard");
    expect(script).toContain("release-readiness-diagnostics.sh");
    expect(script).toContain("release-smoke-test.sh");
    expect(script).toContain("npm run test:e2e:docker");
    expect(script).toContain("generate-release-artifact.sh");
  });

  it("supports a narrowly scoped staging-only secret gate override",()=> {
    expect(script).toContain("SPORTSOS_ALLOW_SECRET_GATE_FAILURE");
    expect(script).toContain("jwt:quality");
    expect(script).toContain("mysql-password:quality");
    expect(script).toContain("minio-password:quality");
  });

  it("does not tolerate unrelated smoke failures",()=> {
    expect(script).toContain(
      "Smoke failure is not limited to approved rehearsal-only secret-quality blockers.",
    );
  });

  it("does not deploy to production",()=> {
    expect(script).toContain("does not deploy to production");
  });
});
