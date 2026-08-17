import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 8.8 multi-round bracket UI", () => {
  it("uses the multi-round bracket tree", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/bracket/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("buildTournamentBracketTree");
    expect(route).toContain("tree");
  });

  it("renders all rounds from the bracket tree", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBracketView.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("tree.rounds.map");
    expect(component).toContain(
      "tournament-bracket-round-",
    );
    expect(component).toContain("TBD");
    expect(component).toContain("BYE");
  });

  it("renders a champion banner when the tree resolves one", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBracketView.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("tree.champion");
    expect(component).toContain(
      'data-testid="tournament-bracket-champion"',
    );
  });
});
