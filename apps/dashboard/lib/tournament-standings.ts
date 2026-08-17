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
