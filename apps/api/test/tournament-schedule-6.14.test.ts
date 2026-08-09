import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const qualification = readFileSync(
  new URL(
    "../src/modules/games/schedule-concurrency-qualification.ts",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.14 concurrency qualification contract", () => {
  it("runs two schedule creates concurrently against the transaction service", () => {
    expect(qualification).toContain("Promise.all([");
    expect(qualification.match(/createGameWithScheduleTransaction/g)?.length).toBeGreaterThanOrEqual(3);
    expect(qualification).toContain("committed === 1 && blocked === 1");
  });

  it("uses temporary identifiable data and cleans committed rows", () => {
    expect(qualification).toContain(
      "SportsOS Milestone 6.14 temporary concurrency qualification",
    );
    expect(qualification).toContain("DELETE FROM games");
    expect(qualification).toContain("createdGameIds");
    expect(qualification).toContain("finally");
  });

  it("requires an existing organization and season instead of creating permanent parents", () => {
    expect(qualification).toContain("FROM seasons s");
    expect(qualification).toContain("JOIN organizations");
    expect(qualification).toContain(
      "requires at least one existing organization with a season",
    );
  });
});
