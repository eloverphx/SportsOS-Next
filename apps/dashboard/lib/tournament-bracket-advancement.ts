import type {
  BracketMatchup,
  BracketSeed,
} from "./tournament-bracket-seeding";

export type BracketMatchupResult = {
  matchupId: string;
  homeScore: number;
  awayScore: number;
  status: string;
};

export type ResolvedBracketMatchup = BracketMatchup & {
  winner: BracketSeed | null;
};

export type BracketAdvancementResult = {
  resolvedRound: ResolvedBracketMatchup[];
  nextRound: BracketMatchup[];
};

function isFinalStatus(status: string): boolean {
  const normalized = status.trim().toUpperCase();

  return (
    normalized === "FINAL" ||
    normalized === "COMPLETE" ||
    normalized === "COMPLETED"
  );
}

function winnerFromResult(
  matchup: BracketMatchup,
  result: BracketMatchupResult | undefined,
): BracketSeed | null {
  if (matchup.bye) {
    return matchup.homeSeed ?? matchup.awaySeed ?? null;
  }

  if (
    !matchup.homeSeed ||
    !matchup.awaySeed ||
    !result ||
    !isFinalStatus(result.status)
  ) {
    return null;
  }

  if (
    !Number.isFinite(result.homeScore) ||
    !Number.isFinite(result.awayScore)
  ) {
    throw new Error(
      `Invalid score for matchup ${matchup.id}.`,
    );
  }

  if (result.homeScore === result.awayScore) {
    return null;
  }

  return result.homeScore > result.awayScore
    ? matchup.homeSeed
    : matchup.awaySeed;
}

export function advanceBracketRound(
  round: BracketMatchup[],
  results: BracketMatchupResult[],
): BracketAdvancementResult {
  const resultsById = new Map(
    results.map((result) => [
      result.matchupId,
      result,
    ]),
  );

  const resolvedRound: ResolvedBracketMatchup[] =
    round.map((matchup) => ({
      ...matchup,
      winner: winnerFromResult(
        matchup,
        resultsById.get(matchup.id),
      ),
    }));

  if (resolvedRound.length <= 1) {
    return {
      resolvedRound,
      nextRound: [],
    };
  }

  const nextRound: BracketMatchup[] = [];

  for (
    let index = 0;
    index < resolvedRound.length;
    index += 2
  ) {
    const left = resolvedRound[index];
    const right = resolvedRound[index + 1];

    if (!left) {
      continue;
    }

    nextRound.push({
      id: `round-${left.round + 1}-slot-${Math.floor(index / 2) + 1}`,
      round: left.round + 1,
      slot: Math.floor(index / 2) + 1,
      homeSeed: left.winner,
      awaySeed: right?.winner ?? null,
      bye: Boolean(left.winner && !right?.winner),
    });
  }

  return {
    resolvedRound,
    nextRound,
  };
}
