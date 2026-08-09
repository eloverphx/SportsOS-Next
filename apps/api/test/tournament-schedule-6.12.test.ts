import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  scheduleMutationOrganizationIds,
} from "../src/modules/games/schedule-mutations.js";

const mutations = readFileSync(
  new URL("../src/modules/games/schedule-mutations.ts", import.meta.url),
  "utf8",
);

const routes = readFileSync(
  new URL("../src/modules/games/routes.ts", import.meta.url),
  "utf8",
);

const enforcement = readFileSync(
  new URL("../src/modules/games/schedule-enforcement.ts", import.meta.url),
  "utf8",
);

describe("Tournament scheduling 6.12 transaction/concurrency hardening", () => {
  it("locks affected organizations in deterministic order", () => {
    expect(scheduleMutationOrganizationIds(null, 9)).toEqual([9]);
    expect(scheduleMutationOrganizationIds(9, 9)).toEqual([9]);
    expect(scheduleMutationOrganizationIds(12, 9)).toEqual([9, 12]);
    expect(scheduleMutationOrganizationIds(9, 12)).toEqual([9, 12]);
  });

  it("uses one transaction connection for schedule validation and writes", () => {
    expect(mutations).toContain("await connection.beginTransaction()");
    expect(mutations).toContain("FOR UPDATE");
    expect(mutations).toContain("listGamesByOrganizationUsingConnection(connection");
    expect(mutations).toContain("listGameTeamOptionsUsingConnection(connection)");
    expect(mutations).toContain("createGameUsingConnection(connection, input)");
    expect(mutations).toContain("updateGameUsingConnection(");
    expect(mutations).toContain("await connection.commit()");
    expect(mutations).toContain("await connection.rollback()");
    expect(mutations).toContain("connection.release()");
  });

  it("checks conflicts after obtaining the organization lock and before writing", () => {
    const createStart = mutations.indexOf(
      "export async function createGameWithScheduleTransaction",
    );
    const updateStart = mutations.indexOf(
      "export async function updateGameWithScheduleTransaction",
    );

    const create = mutations.slice(createStart, updateStart);
    const update = mutations.slice(updateStart);

    expect(create.indexOf("lockOrganizations")).toBeLessThan(
      create.indexOf("evaluateInsideTransaction"),
    );
    expect(create.indexOf("evaluateInsideTransaction")).toBeLessThan(
      create.indexOf("createGameUsingConnection"),
    );

    expect(update.indexOf("lockOrganizations")).toBeLessThan(
      update.indexOf("evaluateInsideTransaction"),
    );
    expect(update.indexOf("evaluateInsideTransaction")).toBeLessThan(
      update.indexOf("updateGameUsingConnection"),
    );
  });

  it("routes POST and PUT through transactional schedule mutations", () => {
    expect(routes).toContain("createGameWithScheduleTransaction(");
    expect(routes).toContain("updateGameWithScheduleTransaction(");
    expect(routes).not.toContain("const game = await createGame(parsed.data)");
    expect(routes).not.toContain("const game = await updateGame(id.data, parsed.data)");
  });

  it("treats organization moves as schedule-relevant", () => {
    expect(enforcement).toContain(
      "existing.organizationId !== input.organizationId",
    );
  });
});
