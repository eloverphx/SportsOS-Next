import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const root = JSON.parse(readFileSync("package.json", "utf8"));
const dashboard = JSON.parse(readFileSync("apps/dashboard/package.json", "utf8"));
const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const doc = readFileSync(
  "docs/MILESTONE-36-SHARP-SECURITY-REMEDIATION.md",
  "utf8",
);

const parts = (v: string) => v.split(".").map(Number);
const gte = (v: string, min: string) => {
  const a = parts(v), b = parts(min);
  for (let i = 0; i < 3; i += 1) {
    if ((a[i] ?? 0) > (b[i] ?? 0)) return true;
    if ((a[i] ?? 0) < (b[i] ?? 0)) return false;
  }
  return true;
};

describe("Milestone 36.8 Sharp security remediation", () => {
  it("resolves Sharp to the supported patched 0.35 line", () => {
    const sharp = lock.packages["node_modules/sharp"].version;
    expect(sharp.startsWith("0.35.")).toBe(true);
    expect(gte(sharp, "0.35.3")).toBe(true);
  });

  it("keeps Sharp transitive instead of adding a direct root dependency", () => {
    expect(root.dependencies?.sharp).toBeUndefined();
    expect(root.devDependencies?.sharp).toBeUndefined();
  });

  it("preserves prior security baselines", () => {
    expect(dashboard.dependencies.next).toBe("15.5.24");
    expect(root.devDependencies["@playwright/test"]).toBe("1.62.1");
    expect(api.dependencies["@fastify/jwt"]).toBe("10.2.2");
    expect(api.dependencies["@fastify/swagger-ui"]).toBe("6.1.1");
    expect(lock.packages["node_modules/fast-uri"].version).toBe("3.1.6");
    expect(
      lock.packages["node_modules/fast-json-stringify/node_modules/fast-uri"]
        .version,
    ).toBe("4.1.3");
    expect(lock.packages["node_modules/nanoid"].version).toBe("3.3.18");
  });

  it("documents the legitimate Sharp platform/runtime lockfile expansion", () => {
    expect(doc).toContain("@img/sharp");
    expect(doc).toContain("@emnapi/runtime");
  });

  it("documents residual PostCSS and MinIO findings separately", () => {
    expect(doc).toContain("PostCSS");
    expect(doc).toContain("MinIO");
    expect(doc).toContain("Next.js 16");
  });
});
