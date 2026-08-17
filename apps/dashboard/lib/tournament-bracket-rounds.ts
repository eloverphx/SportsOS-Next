import type {
  BracketMatchup,
  BracketSeed,
  BracketSeedResult,
} from "./tournament-bracket-seeding";
import type {
  BracketMatchupResult,
} from "./tournament-bracket-advancement";
import {
  advanceBracketRound,
} from "./tournament-bracket-advancement";

export type TournamentBracketRound = {
  round: number;
  name: string;
  matchups: BracketMatchup[];
};

export type TournamentBracketTree = {
  fieldSize: number;
  bracketSize: number;
  rounds: TournamentBracketRound[];
  champion: BracketSeed | null;
};

function roundName(
  round: number,
  totalRounds: number,
): string {
  const remaining = totalRounds - round + 1;

  if (remaining === 1) return "Championship";
  if (remaining === 2) return "Semifinals";
  if (remaining === 3) return "Quarterfinals";

  return `Round ${round}`;
}

function totalRoundsForBracketSize(
  bracketSize: number,
): number {
  if (bracketSize <= 1) {
    return bracketSize === 1 ? 1 : 0;
  }

  return Math.log2(bracketSize);
}

export function buildTournamentBracketTree(
  seedResult: BracketSeedResult,
  results: BracketMatchupResult[],
): TournamentBracketTree {
  if (seedResult.bracketSize === 0) {
    return {
      fieldSize: 0,
      bracketSize: 0,
      rounds: [],
      champion: null,
    };
  }

  const totalRounds =
    totalRoundsForBracketSize(seedResult.bracketSize);

  const rounds: TournamentBracketRound[] = [];
  let currentRound = seedResult.firstRound;
  let champion: BracketSeed | null = null;

  for (
    let roundNumber = 1;
    roundNumber <= totalRounds;
    roundNumber += 1
  ) {
    rounds.push({
      round: roundNumber,
      name: roundName(roundNumber, totalRounds),
      matchups: currentRound,
    });

    if (currentRound.length === 0) {
      break;
    }

    const advancement = advanceBracketRound(
      currentRound,
      results,
    );

    if (currentRound.length === 1) {
      champion =
        advancement.resolvedRound[0]?.winner ?? null;
      break;
    }

    currentRound = advancement.nextRound;
  }

  return {
    fieldSize: seedResult.fieldSize,
    bracketSize: seedResult.bracketSize,
    rounds,
    champion,
  };
}
