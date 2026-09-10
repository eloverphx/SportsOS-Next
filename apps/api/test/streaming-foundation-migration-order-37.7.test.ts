import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const migrationFile = path.resolve(
  __dirname,
  "../src/infrastructure/streaming-foundation-migrations.ts",
);

describe("M37.7 streaming foundation migration ordering", () => {
  it("keeps the logo backfill inside ensureMediaOwnershipColumns", () => {
    const source = fs.readFileSync(migrationFile, "utf8");

    const functionStart = source.indexOf("async function ensureMediaOwnershipColumns");

    const nextFunction = source.indexOf("async function ensureUserAccountColumns");

    const logoUpdate = source.indexOf("WHERE object_key LIKE 'logos/%'");

    expect(functionStart).toBeGreaterThanOrEqual(0);
    expect(nextFunction).toBeGreaterThan(functionStart);
    expect(logoUpdate).toBeGreaterThan(functionStart);
    expect(logoUpdate).toBeLessThan(nextFunction);
  });

  it("runs media ownership migration through the migration entry point", () => {
    const source = fs.readFileSync(migrationFile, "utf8");

    const runner = source.indexOf("export async function runStreamingFoundationMigrations");

    const call = source.indexOf("await ensureMediaOwnershipColumns();", runner);

    expect(runner).toBeGreaterThanOrEqual(0);
    expect(call).toBeGreaterThan(runner);
  });
});
