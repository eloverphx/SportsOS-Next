import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildTournamentCompetitionOperationsSummary,
} from "../lib/tournament-competition-operations";

describe("Milestone 8.10 tournament standings / bracket operations dashboard", () => {
  it("reports tournament completion when a champion resolves", () => {
    const summary =
      buildTournamentCompetitionOperationsSummary({
        totalTeams: 8,
        finalizedGames: 12,
        scheduledGames: 12,
        seededTeams: 8,
        resolvedBracketMatchups: 7,
        totalBracketMatchups: 7,
        championResolved: true,
      });

    expect(summary.stage).toBe("COMPLETE");
    expect(summary.progressPercent).toBe(100);
  });

  it("reports active bracket progression", () => {
    const summary =
      buildTournamentCompetitionOperationsSummary({
        totalTeams: 8,
        finalizedGames: 10,
        scheduledGames: 12,
        seededTeams: 8,
        resolvedBracketMatchups: 4,
        totalBracketMatchups: 7,
        championResolved: false,
      });

    expect(summary.stage).toBe("BRACKET_ACTIVE");
  });

  it("renders the operations dashboard", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentCompetitionOperationsDashboard.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="tournament-competition-operations-dashboard"',
    );
    expect(component).toContain("/tournament/standings");
    expect(component).toContain("/tournament/bracket");
  });

  it("provides the tournament competition dashboard page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Tournament Competition Dashboard",
    );
    expect(page).toContain(
      "TournamentCompetitionOperationsDashboard",
    );
  });
});
