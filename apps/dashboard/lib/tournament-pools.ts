import type {
  TournamentStandingGame,
  TournamentStandingRow,
  TournamentStandingTeam,
} from "./tournament-standings";
import {
  buildTournamentStandings,
} from "./tournament-standings";

export type TournamentPool = {
  id: string;
  name: string;
  teamIds: string[];
};

export type TournamentPoolStandings = {
  poolId: string;
  poolName: string;
  standings: TournamentStandingRow[];
};

export function buildTournamentPoolStandings(
  pools: TournamentPool[],
  teams: TournamentStandingTeam[],
  games: TournamentStandingGame[],
): TournamentPoolStandings[] {
  const teamsById = new Map(teams.map((team) => [team.id, team]));

  return pools.map((pool) => {
    const poolTeams = pool.teamIds
      .map((teamId) => teamsById.get(teamId))
      .filter(
        (team): team is TournamentStandingTeam =>
          Boolean(team),
      );

    const poolTeamIds = new Set(poolTeams.map((team) => team.id));

    const poolGames = games.filter(
      (game) =>
        poolTeamIds.has(game.homeTeamId) &&
        poolTeamIds.has(game.awayTeamId),
    );

    return {
      poolId: pool.id,
      poolName: pool.name,
      standings: buildTournamentStandings(
        poolTeams,
        poolGames,
      ),
    };
  });
}

export function deriveDefaultPools(
  teams: TournamentStandingTeam[],
): TournamentPool[] {
  if (teams.length === 0) {
    return [];
  }

  return [
    {
      id: "all",
      name: "All Teams",
      teamIds: teams.map((team) => team.id),
    },
  ];
}
