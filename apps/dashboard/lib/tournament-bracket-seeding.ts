import type {
  TournamentStandingRow,
} from "./tournament-standings";

export type BracketSeed = {
  seed: number;
  teamId: string;
  teamName: string;
};

export type BracketMatchup = {
  id: string;
  round: number;
  slot: number;
  homeSeed: BracketSeed | null;
  awaySeed: BracketSeed | null;
  bye: boolean;
};

export type BracketSeedResult = {
  fieldSize: number;
  bracketSize: number;
  seeds: BracketSeed[];
  firstRound: BracketMatchup[];
};

function nextPowerOfTwo(value: number): number {
  if (value <= 1) return 1;

  let power = 1;

  while (power < value) {
    power *= 2;
  }

  return power;
}

function assertUniqueTeams(
  standings: TournamentStandingRow[],
): void {
  const seen = new Set<string>();

  for (const row of standings) {
    if (seen.has(row.teamId)) {
      throw new Error(
        `Duplicate team in standings: ${row.teamId}`,
      );
    }

    seen.add(row.teamId);
  }
}

export function seedBracket(
  standings: TournamentStandingRow[],
): BracketSeedResult {
  assertUniqueTeams(standings);

  const ranked = [...standings].sort(
    (left, right) => left.rank - right.rank,
  );

  const seeds: BracketSeed[] = ranked.map((row, index) => ({
    seed: index + 1,
    teamId: row.teamId,
    teamName: row.teamName,
  }));

  const fieldSize = seeds.length;
  const bracketSize =
    fieldSize === 0 ? 0 : nextPowerOfTwo(fieldSize);

  if (bracketSize === 0) {
    return {
      fieldSize,
      bracketSize,
      seeds,
      firstRound: [],
    };
  }

  const slots = Array.from(
    { length: bracketSize },
    (_, index) => seeds[index] ?? null,
  );

  const firstRound: BracketMatchup[] = [];
  const matchupCount = bracketSize / 2;

  for (let index = 0; index < matchupCount; index += 1) {
    const highSeed = slots[index] ?? null;
    const lowSeed =
      slots[bracketSize - 1 - index] ?? null;

    firstRound.push({
      id: `round-1-slot-${index + 1}`,
      round: 1,
      slot: index + 1,
      homeSeed: highSeed,
      awaySeed: lowSeed,
      bye: Boolean(highSeed && !lowSeed),
    });
  }

  return {
    fieldSize,
    bracketSize,
    seeds,
    firstRound,
  };
}
