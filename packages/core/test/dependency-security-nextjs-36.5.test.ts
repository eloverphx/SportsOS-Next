import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = JSON.parse(readFileSync("package.json", "utf8"));
const dashboard = JSON.parse(readFileSync("apps/dashboard/package.json", "utf8"));
const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const doc = readFileSync(
  "docs/MILESTONE-36-NEXTJS-15-SECURITY-REMEDIATION.md",
  "utf8",
);

describe("Milestone 36.5 Next.js 15 security remediation", () => {
  it("updates the dashboard to Next.js 15.5.24", () => {
    expect(dashboard.dependencies.next).toBe("15.5.24");
    expect(lock.packages["node_modules/next"].version).toBe("15.5.24");
  });

  it("does not keep unsupported PostCSS or Sharp overrides", () => {
    expect(root.overrides?.postcss).toBeUndefined();
    expect(root.overrides?.sharp).toBeUndefined();
  });

  it("records the actual Next.js 15.5.24 dependency declarations", () => {
    expect(lock.packages["node_modules/next"].dependencies.postcss).toBe("8.4.31");
    expect(lock.packages["node_modules/next"].optionalDependencies.sharp).toBe(
      "^0.34.3 || ^0.35.3",
    );
  });

  it("does not bundle a Next.js 16 or Playwright migration", () => {
    expect(dashboard.dependencies.next.startsWith("15.")).toBe(true);
    expect(root.devDependencies["@playwright/test"]).toBe("1.55.0");
  });

  it("preserves React and prior API security remediations", () => {
    expect(dashboard.dependencies.react).toBe("19.2.0");
    expect(dashboard.dependencies["react-dom"]).toBe("19.2.0");
    expect(api.dependencies["@fastify/jwt"]).toBe("10.2.2");
    expect(api.dependencies["@fastify/swagger-ui"]).toBe("6.1.1");
  });

  it("documents residual PostCSS/Sharp risk and validation gates", () => {
    expect(doc).toContain("residual");
    expect(doc).toContain("PostCSS");
    expect(doc).toContain("Sharp");
    expect(doc).toContain("Next.js 16");
    expect(doc).toContain("npm audit");
    expect(doc).toContain("Docker E2E");
  });
});
