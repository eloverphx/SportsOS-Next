import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(__dirname, "../../..");

function readJson(relativePath: string): any {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

describe("Milestone 36.10.2 Next.js 16 security baseline", () => {
  it("pins dashboard Next.js exactly to 16.3.4", () => {
    const pkg = readJson("apps/dashboard/package.json");
    expect(pkg.dependencies.next).toBe("16.3.4");
    expect(pkg.dependencies.react).toBe("19.2.0");
    expect(pkg.dependencies["react-dom"]).toBe("19.2.0");
  });

  it("resolves Next.js 16.3.4 and patched PostCSS", () => {
    const lock = readJson("package-lock.json");
    const packages = lock.packages ?? {};

    expect(packages["node_modules/next"]?.version).toBe("16.3.4");

    const postcssVersion = packages["node_modules/postcss"]?.version;
    expect(postcssVersion).toBe("8.5.23");
  });

  it("uses the Next.js 16 proxy convention", () => {
    const proxyPath = path.join(root, "apps/dashboard/proxy.ts");
    const middlewarePath = path.join(root, "apps/dashboard/middleware.ts");

    expect(fs.existsSync(proxyPath)).toBe(true);
    expect(fs.existsSync(middlewarePath)).toBe(false);

    const proxy = fs.readFileSync(proxyPath, "utf8");
    expect(proxy).toContain("export function proxy(");
    expect(proxy).not.toContain("export function middleware(");
  });

  it("preserves dashboard security headers and matcher", () => {
    const proxy = fs.readFileSync(path.join(root, "apps/dashboard/proxy.ts"), "utf8");

    expect(proxy).toContain("Content-Security-Policy");
    expect(proxy).toContain("Strict-Transport-Security");
    expect(proxy).toContain("X-Content-Type-Options");
    expect(proxy).toContain("X-Frame-Options");
    expect(proxy).toContain('"/((?!_next/static|_next/image|favicon.ico).*)"');
  });

  it("records the controlled migration policy", () => {
    const doc = fs.readFileSync(
      path.join(root, "docs/MILESTONE-36-NEXT16-POSTCSS-SECURITY-MIGRATION.md"),
      "utf8",
    );

    expect(doc).toContain("Next.js 16.3.4");
    expect(doc).toContain("PostCSS 8.5.23");
    expect(doc).toContain("npm audit fix --force");
    expect(doc).toContain("middleware.ts");
    expect(doc).toContain("proxy.ts");
  });
});
