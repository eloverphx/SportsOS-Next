import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const source = readFileSync(
  new URL("../src/services/durableGoLiveBridge.ts", import.meta.url),
  "utf8",
);

describe("M40.2b finalized recording lifecycle protection", () => {
  it("does not let late go-live synchronization downgrade finalized recordings", () => {
    expect(source).toContain("AND media_asset_id IS NULL");
    expect(source).toContain("AND status NOT IN ('READY', 'ARCHIVED')");
  });

  it("keeps COMPLETE mapped to PROCESSING for recordings that are not finalized yet", () => {
    expect(source).toContain('case "COMPLETE":');
    expect(source).toContain('return "PROCESSING";');
  });
});
