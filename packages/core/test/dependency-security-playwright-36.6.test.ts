import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = JSON.parse(readFileSync("package.json", "utf8"));
const dashboard = JSON.parse(readFileSync("apps/dashboard/package.json", "utf8"));
const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const dockerE2E = readFileSync("scripts/test-e2e-docker.sh", "utf8");
const documentation = readFileSync(
  "docs/MILESTONE-36-PLAYWRIGHT-SECURITY-REMEDIATION.md",
  "utf8",
);

describe("Milestone 36.6 Playwright security remediation", () => {
  it("pins @playwright/test to 1.62.1", () => {
    expect(root.devDependencies["@playwright/test"]).toBe("1.62.1");
    expect(lock.packages["node_modules/@playwright/test"].version).toBe("1.62.1");
  });

  it("resolves the Playwright runtime packages to 1.62.1", () => {
    expect(lock.packages["node_modules/playwright"].version).toBe("1.62.1");
    expect(lock.packages["node_modules/playwright-core"].version).toBe("1.62.1");
  });

  it("keeps Docker E2E synchronized with the installed Playwright version", () => {
    expect(dockerE2E).toContain(
      'node -p "require(\'@playwright/test/package.json\').version"',
    );
    expect(dockerE2E).toContain(
      '"mcr.microsoft.com/playwright:v${PLAYWRIGHT_VERSION}-noble"',
    );
  });

  it("does not bundle the Next.js 16 migration", () => {
    expect(dashboard.dependencies.next).toBe("15.5.24");
    expect(dashboard.dependencies.next.startsWith("15.")).toBe(true);
    expect(dashboard.dependencies.react).toBe("19.2.0");
    expect(dashboard.dependencies["react-dom"]).toBe("19.2.0");
  });

  it("preserves previous API security remediations", () => {
    expect(api.dependencies["@fastify/jwt"]).toBe("10.2.2");
    expect(api.dependencies["@fastify/swagger-ui"]).toBe("6.1.1");
  });

  it("documents focused validation and residual audit review", () => {
    expect(documentation).toContain("1.62.1");
    expect(documentation).toContain("Docker E2E");
    expect(documentation).toContain("npm audit");
    expect(documentation).toContain("Next.js 16");
    expect(documentation).toContain("fast-uri");
    expect(documentation).toContain("nanoid");
  });
});
