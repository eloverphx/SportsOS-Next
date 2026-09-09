import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const ci = readFileSync(".github/workflows/ci.yml", "utf8");
const dependabot = readFileSync(".github/dependabot.yml", "utf8");
const preflight = readFileSync("scripts/release-governance-preflight.sh", "utf8");
const doc = readFileSync("docs/MILESTONE-36-SECURITY-RELEASE-CLOSEOUT.md", "utf8");
const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));

const checkoutSha = "11d5960a326750d5838078e36cf38b85af677262";
const setupNodeSha = "49933ea5288caeca8642d1e84afbd3f7d6820020";

describe("Milestone 36.12 security and release governance closeout", () => {
  it("pins GitHub Actions to immutable reviewed commits", () => {
    expect(ci).toContain(`actions/checkout@${checkoutSha}`);
    expect(ci).toContain(`actions/setup-node@${setupNodeSha}`);

    expect(ci).not.toContain("actions/checkout@v4");
    expect(ci).not.toContain("actions/setup-node@v4");
  });

  it("pins the patched Vitest security baseline", () => {
    expect(api.devDependencies.vitest).toBe("4.1.11");
    expect(doc).toContain("Vitest: `4.1.11`");
  });

  it("keeps GitHub Actions dependency monitoring enabled", () => {
    expect(dependabot).toContain("package-ecosystem: github-actions");
    expect(dependabot).toContain("interval: weekly");
  });

  it("makes the preflight enforce the exact reviewed action pins", () => {
    expect(preflight).toContain(`actions/checkout@${checkoutSha}`);
    expect(preflight).toContain(`actions/setup-node@${setupNodeSha}`);
  });

  it("accepts only the documented residual dependency package set", () => {
    expect(preflight).toContain('"decode-uri-component"');
    expect(preflight).toContain('"minio"');
    expect(preflight).toContain('"query-string"');
    expect(preflight).toContain('"stream-json"');
    expect(preflight).toContain("high or critical");
    expect(preflight).toContain("unexpected dependency findings");
  });

  it("keeps the governance preflight non-mutating", () => {
    expect(preflight).not.toMatch(/(^|\n)\s*git\s+push(?:\s|$)/);
    expect(preflight).not.toMatch(/(^|\n)\s*git\s+merge(?:\s|$)/);
    expect(preflight).not.toMatch(/(^|\n)\s*git\s+tag\s+-a(?:\s|$)/);
    expect(preflight).not.toMatch(/(^|\n)\s*npm\s+audit\s+fix(?:\s|$)/);
  });

  it("records the verified GitHub ruleset limits without overstating protection", () => {
    expect(doc).toContain("ruleset named `lock`");
    expect(doc).toContain("prevents branch deletion");
    expect(doc).toContain("prevents non-fast-forward");
    expect(doc).toContain("does **not** currently require CI status checks");
    expect(doc).toContain("must not describe the repository as having mandatory");
  });

  it("requires exact-CI verification before the M36 release tag", () => {
    expect(doc).toContain("sportsos-m36-complete");
    expect(doc).toContain("GitHub CI is green for that exact commit");
    expect(doc).toContain("tag must be annotated");
  });
});
