import fs from "node:fs";
import { describe, expect, it } from "vitest";

const preflight = fs.readFileSync(
  "scripts/release-governance-preflight.sh",
  "utf8",
);
const ci = fs.readFileSync(
  ".github/workflows/ci.yml",
  "utf8",
);
const dependabot = fs.readFileSync(
  ".github/dependabot.yml",
  "utf8",
);
const prTemplate = fs.readFileSync(
  ".github/PULL_REQUEST_TEMPLATE.md",
  "utf8",
);

describe("Milestone 36.1 release governance baseline", () => {
  it("preserves least-privilege CI and the full repository verification path", () => {
    expect(ci).toContain("permissions:");
    expect(ci).toContain("contents: read");
    expect(ci).toContain("npm run lint");
    expect(ci).toContain("npm run typecheck");
    expect(ci).toContain("npm run test");
    expect(ci).toContain("npm run build");
    expect(ci).toContain("npm run test:e2e");
  });

  it("keeps automated dependency monitoring for npm and GitHub Actions", () => {
    expect(dependabot).toContain("package-ecosystem: npm");
    expect(dependabot).toContain("package-ecosystem: github-actions");
  });

  it("requires annotated release lineage and synchronized main", () => {
    expect(preflight).toContain("git cat-file -t");
    expect(preflight).toContain("git merge-base --is-ancestor");
    expect(preflight).toContain("refs/remotes/origin/main");
    expect(preflight).toContain('BRANCH" == "main"');
  });

  it("guards local-only and runtime state from release commits", () => {
    expect(preflight).toContain("a real .env file is tracked");
    expect(preflight).toContain(".game-engine-backups content is tracked");
    expect(preflight).toContain("runtime data/ content is tracked");
  });

  it("adds dependency and release review requirements to pull requests", () => {
    expect(prTemplate).toContain("SPORTSOS_M36_1_RELEASE_GOVERNANCE");
    expect(prTemplate).toContain("Security-related dependency updates");
    expect(prTemplate).toContain("Major-version dependency upgrades");
    expect(prTemplate).toContain("Release tags are annotated");
  });

  it("keeps npm audit opt-in until dependency remediation is completed", () => {
    expect(preflight).toContain("SPORTSOS_RUN_NPM_AUDIT");
    expect(preflight).toContain("npm audit --json");
    expect(preflight).not.toContain("npm audit fix");
  });

  it("does not grant mutation authority to the governance preflight", () => {
    expect(preflight).not.toMatch(/(^|\n)\s*git\s+push(?:\s|$)/);
    expect(preflight).not.toMatch(/(^|\n)\s*git\s+merge(?:\s|$)/);
    expect(preflight).not.toMatch(/(^|\n)\s*git\s+tag\s+-a(?:\s|$)/);
    expect(preflight).not.toMatch(/(^|\n)\s*npm\s+audit\s+fix(?:\s|$)/);
  });
});
