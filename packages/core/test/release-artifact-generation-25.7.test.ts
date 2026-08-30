import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.7 release artifact / changelog generation", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/generate-release-artifact.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("captures release identity",()=> {
    expect(script).toContain("git rev-parse HEAD");
    expect(script).toContain("git branch --show-current");
    expect(script).toContain("git describe --tags --exact-match HEAD");
    expect(script).toContain("Dirty working tree");
  });

  it("captures recent changelog history",()=> {
    expect(script).toContain("git log -15");
    expect(script).toContain("## Recent Changes");
  });

  it("includes prior acceptance milestones",()=> {
    expect(script).toContain("MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md");
    expect(script).toContain("MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md");
  });

  it("includes deployment verification commands",()=> {
    expect(script).toContain("npm run typecheck && npm test");
    expect(script).toContain("bash scripts/release-smoke-test.sh");
    expect(script).toContain("npm run test:e2e:docker");
  });

  it("writes to release-artifacts by default",()=> {
    expect(script).toContain("release-artifacts");
    expect(script).toContain("SPORTSOS_RELEASE_ARTIFACT_DIR");
  });
});
