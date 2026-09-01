import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const root = JSON.parse(readFileSync("package.json", "utf8"));
const dashboard = JSON.parse(readFileSync("apps/dashboard/package.json", "utf8"));
const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const doc = readFileSync(
  "docs/MILESTONE-36-FAST-URI-NANOID-SECURITY-REMEDIATION.md",
  "utf8",
);

const parts = (v: string) => v.split(".").map(Number);
const gte = (v: string, min: string) => {
  const a = parts(v);
  const b = parts(min);
  for (let i = 0; i < 3; i += 1) {
    if ((a[i] ?? 0) > (b[i] ?? 0)) return true;
    if ((a[i] ?? 0) < (b[i] ?? 0)) return false;
  }
  return true;
};

describe("Milestone 36.7 fast-uri/nanoid security remediation", () => {
  it("resolves patched fast-uri versions without crossing majors", () => {
    const f3 = lock.packages["node_modules/fast-uri"].version;
    const f4 =
      lock.packages["node_modules/fast-json-stringify/node_modules/fast-uri"]
        .version;

    expect(f3.startsWith("3.")).toBe(true);
    expect(f4.startsWith("4.")).toBe(true);
    expect(gte(f3, "3.1.5")).toBe(true);
    expect(gte(f4, "4.1.2")).toBe(true);
  });

  it("resolves nanoid to the patched 3.x line", () => {
    const nanoid = lock.packages["node_modules/nanoid"].version;
    expect(nanoid.startsWith("3.")).toBe(true);
    expect(gte(nanoid, "3.3.18")).toBe(true);
  });

  it("does not add fast-uri or nanoid as direct dependencies", () => {
    expect(root.dependencies?.["fast-uri"]).toBeUndefined();
    expect(root.dependencies?.nanoid).toBeUndefined();
    expect(root.devDependencies?.["fast-uri"]).toBeUndefined();
    expect(root.devDependencies?.nanoid).toBeUndefined();
  });

  it("preserves prior security baselines", () => {
    expect(root.devDependencies["@playwright/test"]).toBe("1.62.1");
    expect(dashboard.dependencies.next).toBe("15.5.24");
    expect(api.dependencies["@fastify/jwt"]).toBe("10.2.2");
    expect(api.dependencies["@fastify/swagger-ui"]).toBe("6.1.1");
  });

  it("documents that remaining Next.js and MinIO findings are separate", () => {
    expect(doc).toContain("PostCSS");
    expect(doc).toContain("Sharp");
    expect(doc).toContain("MinIO");
    expect(doc).toContain("npm audit");
  });
});
