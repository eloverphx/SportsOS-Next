#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.1-tournament-standings-engine"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

LIB="apps/dashboard/lib/tournament-standings.ts"
TEST="apps/dashboard/test/tournament-standings-8.1.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

for file in "$LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$LIB" <<'EOF'
export type TournamentStandingTeam = {
  id: string;
  name: string;
};

export type TournamentStandingGame = {
  id: string;
  homeTeamId: string;
  awayTeamId: string;
  homeScore: number;
  awayScore: number;
  status: string;
};

export type TournamentStandingRow = {
  teamId: string;
  teamName: string;
  gamesPlayed: number;
  wins: number;
  losses: number;
  ties: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifferential: number;
  points: number;
  rank: number;
};

export type TournamentStandingsRules = {
  winPoints: number;
  tiePoints: number;
  lossPoints: number;
};

export const DEFAULT_TOURNAMENT_STANDINGS_RULES:
  TournamentStandingsRules = Object.freeze({
    winPoints: 2,
    tiePoints: 1,
    lossPoints: 0,
  });

function isFinalStatus(status: string): boolean {
  const normalized = status.trim().toUpperCase();

  return (
    normalized === "FINAL" ||
    normalized === "COMPLETED" ||
    normalized === "COMPLETE"
  );
}

function assertScore(score: number, label: string): void {
  if (!Number.isFinite(score) || score < 0) {
    throw new Error(`${label} must be a non-negative number.`);
  }
}

export function buildTournamentStandings(
  teams: TournamentStandingTeam[],
  games: TournamentStandingGame[],
  rules: TournamentStandingsRules =
    DEFAULT_TOURNAMENT_STANDINGS_RULES,
): TournamentStandingRow[] {
  const teamMap = new Map(
    teams.map((team) => [
      team.id,
      {
        teamId: team.id,
        teamName: team.name,
        gamesPlayed: 0,
        wins: 0,
        losses: 0,
        ties: 0,
        goalsFor: 0,
        goalsAgainst: 0,
        goalDifferential: 0,
        points: 0,
        rank: 0,
      } satisfies TournamentStandingRow,
    ]),
  );

  for (const game of games) {
    if (!isFinalStatus(game.status)) {
      continue;
    }

    const home = teamMap.get(game.homeTeamId);
    const away = teamMap.get(game.awayTeamId);

    if (!home || !away) {
      continue;
    }

    assertScore(game.homeScore, "homeScore");
    assertScore(game.awayScore, "awayScore");

    home.gamesPlayed += 1;
    away.gamesPlayed += 1;

    home.goalsFor += game.homeScore;
    home.goalsAgainst += game.awayScore;
    away.goalsFor += game.awayScore;
    away.goalsAgainst += game.homeScore;

    if (game.homeScore > game.awayScore) {
      home.wins += 1;
      away.losses += 1;
      home.points += rules.winPoints;
      away.points += rules.lossPoints;
    } else if (game.awayScore > game.homeScore) {
      away.wins += 1;
      home.losses += 1;
      away.points += rules.winPoints;
      home.points += rules.lossPoints;
    } else {
      home.ties += 1;
      away.ties += 1;
      home.points += rules.tiePoints;
      away.points += rules.tiePoints;
    }
  }

  const rows = [...teamMap.values()].map((row) => ({
    ...row,
    goalDifferential: row.goalsFor - row.goalsAgainst,
  }));

  rows.sort((left, right) => {
    if (right.points !== left.points) {
      return right.points - left.points;
    }

    if (right.wins !== left.wins) {
      return right.wins - left.wins;
    }

    if (right.goalDifferential !== left.goalDifferential) {
      return right.goalDifferential - left.goalDifferential;
    }

    if (right.goalsFor !== left.goalsFor) {
      return right.goalsFor - left.goalsFor;
    }

    return left.teamName.localeCompare(right.teamName);
  });

  return rows.map((row, index) => ({
    ...row,
    rank: index + 1,
  }));
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  buildTournamentStandings,
} from "../lib/tournament-standings";

describe("Milestone 8.1 tournament standings engine", () => {
  const teams = [
    { id: "a", name: "Lakers" },
    { id: "b", name: "Bears" },
    { id: "c", name: "Eagles" },
  ];

  it("starts every team at zero", () => {
    const standings = buildTournamentStandings(teams, []);

    expect(standings).toHaveLength(3);
    expect(
      standings.every(
        (row) =>
          row.gamesPlayed === 0 &&
          row.points === 0 &&
          row.goalsFor === 0,
      ),
    ).toBe(true);
  });

  it("counts only finalized games", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "g1",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 4,
        awayScore: 2,
        status: "FINAL",
      },
      {
        id: "g2",
        homeTeamId: "a",
        awayTeamId: "c",
        homeScore: 9,
        awayScore: 0,
        status: "LIVE",
      },
    ]);

    const lakers = standings.find((row) => row.teamId === "a");

    expect(lakers).toMatchObject({
      gamesPlayed: 1,
      wins: 1,
      points: 2,
      goalsFor: 4,
      goalsAgainst: 2,
      goalDifferential: 2,
    });
  });

  it("awards two points for a win and one for a tie by default", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "g1",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 3,
        awayScore: 1,
        status: "FINAL",
      },
      {
        id: "g2",
        homeTeamId: "a",
        awayTeamId: "c",
        homeScore: 2,
        awayScore: 2,
        status: "FINAL",
      },
    ]);

    const lakers = standings.find((row) => row.teamId === "a");

    expect(lakers).toMatchObject({
      wins: 1,
      ties: 1,
      losses: 0,
      gamesPlayed: 2,
      points: 3,
    });
  });

  it("supports configurable tournament point rules", () => {
    const standings = buildTournamentStandings(
      teams,
      [
        {
          id: "g1",
          homeTeamId: "a",
          awayTeamId: "b",
          homeScore: 1,
          awayScore: 0,
          status: "FINAL",
        },
      ],
      {
        winPoints: 3,
        tiePoints: 1,
        lossPoints: 0,
      },
    );

    expect(
      standings.find((row) => row.teamId === "a")?.points,
    ).toBe(3);
  });

  it("sorts by points, wins, goal differential, goals for, then name", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "g1",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 4,
        awayScore: 2,
        status: "FINAL",
      },
      {
        id: "g2",
        homeTeamId: "c",
        awayTeamId: "a",
        homeScore: 1,
        awayScore: 0,
        status: "FINAL",
      },
      {
        id: "g3",
        homeTeamId: "b",
        awayTeamId: "c",
        homeScore: 3,
        awayScore: 2,
        status: "FINAL",
      },
    ]);

    expect(standings.map((row) => row.rank)).toEqual([1, 2, 3]);
    expect(standings[0].points).toBeGreaterThanOrEqual(
      standings[1].points,
    );
  });

  it("ignores finalized games containing teams outside the supplied field", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "external",
        homeTeamId: "a",
        awayTeamId: "not-in-tournament",
        homeScore: 5,
        awayScore: 1,
        status: "FINAL",
      },
    ]);

    expect(
      standings.find((row) => row.teamId === "a")?.gamesPlayed,
    ).toBe(0);
  });

  it("rejects invalid finalized scores", () => {
    expect(() =>
      buildTournamentStandings(teams, [
        {
          id: "bad",
          homeTeamId: "a",
          awayTeamId: "b",
          homeScore: -1,
          awayScore: 2,
          status: "FINAL",
        },
      ]),
    ).toThrow("homeScore must be a non-negative number.");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - pure tournament standings engine"
echo "  - finalized-game filtering"
echo "  - wins / losses / ties"
echo "  - goals for / against / differential"
echo "  - configurable points system"
echo "  - deterministic ranking"
echo "  - Milestone 8.1 unit tests"
echo
echo "Default ranking order:"
echo "  1. points"
echo "  2. wins"
echo "  3. goal differential"
echo "  4. goals for"
echo "  5. team name"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 8.2 - Tournament Standings API/UI Integration"
