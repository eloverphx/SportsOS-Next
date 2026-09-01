import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = JSON.parse(readFileSync("package.json", "utf8"));
const api = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const doc = readFileSync(
  "docs/MILESTONE-36-MINIO-RESIDUAL-RISK.md",
  "utf8",
);

const packages = lock.packages ?? {};
const minio =
  packages["apps/api/node_modules/minio"] ?? packages["node_modules/minio"];
const query =
  packages["apps/api/node_modules/query-string"] ??
  packages["node_modules/query-string"];
const decode =
  packages["apps/api/node_modules/decode-uri-component"] ??
  packages["node_modules/decode-uri-component"];

describe("Milestone 36.9.2 MinIO residual risk guard", () => {
  it("preserves the current MinIO dependency baseline", () => {
    expect(api.dependencies.minio).toBe("8.0.7");
    expect(minio.version).toBe("8.0.7");
    expect(query.version).toBe("7.1.3");
    expect(decode.version).toBe("0.2.2");
  });

  it("does not introduce an unsafe dependency override", () => {
    const overrides = JSON.stringify(root.overrides ?? {});
    expect(overrides).not.toContain("decode-uri-component");
    expect(overrides).not.toContain("query-string");
    expect(overrides).not.toContain("minio");
  });

  it("documents the failed compatibility probe", () => {
    expect(doc).toContain("decodeComponent is not a function");
    expect(doc).toContain("decode-uri-component 0.5.0");
    expect(doc).toContain("query-string 7.1.3");
  });

  it("documents the prohibited automated remediations", () => {
    expect(doc).toContain("npm audit fix --force");
    expect(doc).toContain("MinIO to `7.0.26`");
    expect(doc).toContain("must not");
  });

  it("keeps the separate Next.js/PostCSS residual isolated", () => {
    expect(doc).toContain("PostCSS");
    expect(doc).toContain("Next.js 16");
  });
});
