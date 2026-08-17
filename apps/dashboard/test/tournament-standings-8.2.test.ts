import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 8.2 standings API / UI integration", () => {
  it("exposes a tournament standings API route", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/standings/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain('fetch(`${API_BASE_URL}/games`');
    expect(route).toContain("buildTournamentStandings");
  });

  it("keeps standings calculation in the shared 8.1 engine", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/standings/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      'from "../../../../lib/tournament-standings"',
    );
  });

  it("renders the tournament standings table", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentStandingsTable.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="tournament-standings-table"',
    );
    expect(component).toContain("gamesPlayed");
    expect(component).toContain("goalDifferential");
    expect(component).toContain("points");
  });
});
