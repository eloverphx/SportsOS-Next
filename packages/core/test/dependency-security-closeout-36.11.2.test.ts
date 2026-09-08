import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const rootDir = resolve(testDir, "../../..");

function readJson(path: string) {
  return JSON.parse(readFileSync(resolve(rootDir, path), "utf8"));
}

const root = readJson("package.json");
const api = readJson("apps/api/package.json");
const dashboard = readJson("apps/dashboard/package.json");
const lock = readJson("package-lock.json");
const doc = readFileSync(
  resolve(rootDir, "docs/MILESTONE-36-DEPENDENCY-SECURITY-CLOSEOUT.md"),
  "utf8",
);

const packages = lock.packages ?? {};

function lockedPackage(name: string) {
  return packages[`apps/api/node_modules/${name}`] ?? packages[`node_modules/${name}`];
}

describe("Milestone 36.11.2 dependency security closeout", () => {
  it("preserves the remediated direct security baselines", () => {
    expect(api.dependencies.fastify).toBe("5.12.3");
    expect(api.dependencies.minio).toBe("8.0.7");
    expect(dashboard.dependencies.next).toBe("16.3.4");
  });

  it("preserves the documented MinIO residual tree", () => {
    const minio = lockedPackage("minio");
    const queryString = lockedPackage("query-string");
    const decodeUriComponent = lockedPackage("decode-uri-component");
    const streamJson = lockedPackage("stream-json");

    expect(minio.version).toBe("8.0.7");
    expect(queryString.version).toBe("7.1.3");
    expect(decodeUriComponent.version).toBe("0.2.2");
    expect(streamJson).toBeDefined();
    expect(minio.dependencies["query-string"]).toBeDefined();
    expect(minio.dependencies["stream-json"]).toBeDefined();
  });

  it("does not introduce unsafe transitive dependency overrides", () => {
    const overrides = JSON.stringify(root.overrides ?? {});

    expect(overrides).not.toContain("minio");
    expect(overrides).not.toContain("query-string");
    expect(overrides).not.toContain("decode-uri-component");
    expect(overrides).not.toContain("stream-json");
  });

  it("records the current severity closeout", () => {
    expect(doc).toContain("4 moderate");
    expect(doc).toContain("0 high");
    expect(doc).toContain("0 critical");
    expect(doc).toContain("MinIO transitive dependency tree");
  });

  it("records completed Next/PostCSS and Fastify remediation", () => {
    expect(doc).toContain("Next.js was migrated");
    expect(doc).toContain("PostCSS 8.5.23");
    expect(doc).toContain("Fastify was updated to exactly 5.12.3");
  });

  it("continues to prohibit forced audit remediation", () => {
    expect(doc).toContain("npm audit fix --force");
    expect(doc).toContain("backwards major-version change");
  });
});
