import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 8.5 bracket API / UI integration", () => {
  it("uses the shared bracket seeding engine", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/bracket/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("seedBracket");
    expect(route).toContain(
      'from "../../../../lib/tournament-bracket-seeding"',
    );
  });

  it("renders the tournament bracket view", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBracketView.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="tournament-bracket-view"',
    );
    expect(component).toContain("firstRound.map");
    expect(component).toContain("matchup.bye");
  });

  it("provides a tournament bracket page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/bracket/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain("Tournament Bracket");
    expect(page).toContain("TournamentBracketView");
  });
});
