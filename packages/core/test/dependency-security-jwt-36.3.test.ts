import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const apiPackage = JSON.parse(readFileSync("apps/api/package.json", "utf8"));
const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));

describe("Milestone 36.3 critical JWT security remediation", () => {
  it("pins @fastify/jwt to the reviewed security target", () => {
    expect(apiPackage.dependencies["@fastify/jwt"]).toBe("10.2.2");
    expect(lock.packages["node_modules/@fastify/jwt"]?.version).toBe("10.2.2");
  });

  it("resolves fast-jwt beyond the critical vulnerable range", () => {
    const version = String(lock.packages["node_modules/fast-jwt"]?.version ?? "");
    const [major, minor, patch] = version.split(".").map(Number);

    const safe =
      major > 6 ||
      (major === 6 && minor > 2) ||
      (major === 6 && minor === 2 && patch >= 4);

    expect(safe).toBe(true);
  });

  it("does not bundle unrelated dependency upgrades in apps/api package metadata", () => {
    expect(apiPackage.dependencies.fastify).toBe("^5.10.0");
    expect(apiPackage.dependencies["@fastify/rate-limit"]).toBe("^11.1.0");
    expect(apiPackage.dependencies["@fastify/swagger-ui"]).toBe("^6.1.0");
    expect(apiPackage.dependencies.next).toBeUndefined();
  });
});
