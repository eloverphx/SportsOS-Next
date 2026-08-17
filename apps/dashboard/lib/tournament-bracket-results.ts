import type {
  BracketMatchup,
} from "./tournament-bracket-seeding";
import type {
  BracketMatchupResult,
} from "./tournament-bracket-advancement";

export type AuthoritativeTournamentGame = {
  id: string;
  homeTeamId: string;
  awayTeamId: string;
  homeScore: number;
  awayScore: number;
  status: string;
};

function isFinalStatus(status: string): boolean {
  const normalized = status.trim().toUpperCase();

  return (
    normalized === "FINAL" ||
    normalized === "COMPLETE" ||
    normalized === "COMPLETED"
  );
}

function samePair(
  matchup: BracketMatchup,
  game: AuthoritativeTournamentGame,
): boolean {
  if (!matchup.homeSeed || !matchup.awaySeed) {
    return false;
  }

  const bracketHome = matchup.homeSeed.teamId;
  const bracketAway = matchup.awaySeed.teamId;

  return (
    (game.homeTeamId === bracketHome &&
      game.awayTeamId === bracketAway) ||
    (game.homeTeamId === bracketAway &&
      game.awayTeamId === bracketHome)
  );
}

function normalizeScoreOrientation(
  matchup: BracketMatchup,
  game: AuthoritativeTournamentGame,
): {
  homeScore: number;
  awayScore: number;
} {
  if (!matchup.homeSeed || !matchup.awaySeed) {
    return {
      homeScore: 0,
      awayScore: 0,
    };
  }

  if (game.homeTeamId === matchup.homeSeed.teamId) {
    return {
      homeScore: game.homeScore,
      awayScore: game.awayScore,
    };
  }

  return {
    homeScore: game.awayScore,
    awayScore: game.homeScore,
  };
}

export function deriveBracketResultsFromGames(
  matchups: BracketMatchup[],
  games: AuthoritativeTournamentGame[],
): BracketMatchupResult[] {
  const finalizedGames = games.filter((game) =>
    isFinalStatus(game.status),
  );

  return matchups.flatMap((matchup) => {
    if (matchup.bye || !matchup.homeSeed || !matchup.awaySeed) {
      return [];
    }

    const matches = finalizedGames.filter((game) =>
      samePair(matchup, game),
    );

    if (matches.length === 0) {
      return [];
    }

    if (matches.length > 1) {
      throw new Error(
        `Multiple finalized games match bracket matchup ${matchup.id}.`,
      );
    }

    const game = matches[0];

    if (!game) {
      return [];
    }

    if (
      !Number.isFinite(game.homeScore) ||
      !Number.isFinite(game.awayScore)
    ) {
      throw new Error(
        `Invalid authoritative score for game ${game.id}.`,
      );
    }

    const oriented = normalizeScoreOrientation(
      matchup,
      game,
    );

    return [
      {
        matchupId: matchup.id,
        homeScore: oriented.homeScore,
        awayScore: oriented.awayScore,
        status: game.status,
      },
    ];
  });
}
