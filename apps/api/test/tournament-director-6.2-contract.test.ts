import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

describe("Tournament Director 6.2 contract", () => {
  it("groups games by existing venue instead of duplicating rink data", () => {
    expect(page).toContain('row.game.venue?.trim() || "Rink not assigned"');
    expect(page).toContain("const rinkGroups = useMemo");
    expect(page).toContain("rinkGroups.map");
  });

  it("classifies scheduled start urgency", () => {
    expect(page).toContain('return "LATE"');
    expect(page).toContain('return "STARTING_SOON"');
    expect(page).toContain('"LATE START"');
    expect(page).toContain('"STARTING SOON"');
  });

  it("retains authoritative operational feeds and links", () => {
    expect(page).toContain('api<{ games: Game[] }>("/games")');
    expect(page).toContain('api<{ devices: Device[] }>("/scoreboard-devices")');
    expect(page).toContain('api<EngineResponse>("/system/game-engine")');
    expect(page).toContain("`/games/${game.id}/penalties`");
    expect(page).toContain('href={`/games/${game.id}/control`}');
    expect(page).toContain('href={`/games/${game.id}/overlay`}');
  });
});

