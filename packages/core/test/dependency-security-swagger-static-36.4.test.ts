import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const documentation = readFileSync(
  "docs/MILESTONE-36-FASTIFY-SWAGGER-STATIC-SECURITY-REMEDIATION.md",
  "utf8",
);

function greaterThan(actual: string, baseline: string): boolean {
  const a = actual.split(".").map(Number);
  const b = baseline.split(".").map(Number);
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    if (av !== bv) return av > bv;
  }
  return false;
}

describe("Milestone 36.4 Swagger/static security remediation", () => {
  it("pins @fastify/swagger-ui to 6.1.1", () => {
    expect(api.dependencies["@fastify/swagger-ui"]).toBe("6.1.1");
    expect(lock.packages["node_modules/@fastify/swagger-ui"].version).toBe("6.1.1");
  });

  it("resolves @fastify/static outside the vulnerable range", () => {
    const version = lock.packages["node_modules/@fastify/static"].version;
    expect(greaterThan(version, "10.1.1")).toBe(true);
  });

  it("preserves Milestone 36.3 JWT remediation", () => {
    expect(api.dependencies["@fastify/jwt"]).toBe("10.2.2");
    expect(lock.packages["node_modules/@fastify/jwt"].version).toBe("10.2.2");
  });

  it("does not bundle unrelated API dependency upgrades", () => {
    expect(api.dependencies.fastify).toBe("^5.10.0");
    expect(api.dependencies["@fastify/rate-limit"]).toBe("^11.1.0");
  });

  it("documents audit and Docker E2E verification", () => {
    expect(documentation).toContain("@fastify/static");
    expect(documentation).toContain("npm audit");
    expect(documentation).toContain("Docker E2E");
  });
});
