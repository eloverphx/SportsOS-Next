import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const inventory = readFileSync(
  "scripts/dependency-security-inventory.sh",
  "utf8",
);

const documentation = readFileSync(
  "docs/MILESTONE-36-DEPENDENCY-SECURITY-INVENTORY.md",
  "utf8",
);

describe("Milestone 36.2 dependency security inventory", () => {
  it("uses read-only npm audit and outdated inventory commands", () => {
    expect(inventory).toContain("npm audit --json");
    expect(inventory).toContain("npm outdated --json");
    expect(inventory).toContain("sha256sum package.json");
    expect(inventory).toContain("sha256sum package-lock.json");
  });

  it("does not grant package mutation authority", () => {
    expect(inventory).not.toMatch(/(^|\n)\s*npm\s+audit\s+fix(?:\s|$)/);
    expect(inventory).not.toMatch(/(^|\n)\s*npm\s+install(?:\s|$)/);
    expect(inventory).not.toMatch(/(^|\n)\s*npm\s+update(?:\s|$)/);
  });

  it("does not grant GitHub mutation authority", () => {
    expect(inventory).not.toMatch(/(^|\n)\s*git\s+push(?:\s|$)/);
    expect(inventory).not.toMatch(/(^|\n)\s*git\s+merge(?:\s|$)/);
    expect(inventory).not.toMatch(/(^|\n)\s*git\s+tag\s+-a(?:\s|$)/);
  });

  it("classifies major-version jumps separately", () => {
    expect(inventory).toContain("Major-version candidates (manual review required)");
    expect(inventory).toContain("Same-major candidates:");
  });

  it("documents the current security-first remediation order", () => {
    expect(documentation).toContain("@fastify/rate-limit");
    expect(documentation).toContain("fastify");
    expect(documentation).toContain("@fastify/jwt");
    expect(documentation).toContain("Next.js 16");
    expect(documentation).toContain("TypeScript 7");
  });

  it("requires focused remediation rather than grouped dependency churn", () => {
    expect(documentation).toContain("Do not merge PR #5 wholesale");
    expect(documentation).toContain("one security-focused dependency set at a time");
  });
});
