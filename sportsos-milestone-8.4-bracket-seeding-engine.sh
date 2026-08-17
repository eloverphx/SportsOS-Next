#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.4-bracket-seeding-engine"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

STANDINGS_LIB="apps/dashboard/lib/tournament-standings.ts"
BRACKET_LIB="apps/dashboard/lib/tournament-bracket-seeding.ts"
BRACKET_TEST="apps/dashboard/test/tournament-bracket-seeding-8.4.test.ts"

[[ -f "$STANDINGS_LIB" ]] || {
  echo "ERROR: Milestone 8.1 standings engine missing: $STANDINGS_LIB" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$BRACKET_LIB")" \
  "$BACKUP_DIR/$(dirname "$BRACKET_TEST")"

for file in "$BRACKET_LIB" "$BRACKET_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$BRACKET_LIB" <<'EOF'
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
EOF

cat > "$BRACKET_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  seedBracket,
} from "../lib/tournament-bracket-seeding";

function row(
  rank: number,
  teamId: string,
  teamName: string,
) {
  return {
    teamId,
    teamName,
    gamesPlayed: 3,
    wins: 2,
    losses: 1,
    ties: 0,
    goalsFor: 10,
    goalsAgainst: 5,
    goalDifferential: 5,
    points: 4,
    rank,
  };
}

describe("Milestone 8.4 bracket seeding engine", () => {
  it("returns an empty bracket for no teams", () => {
    expect(seedBracket([])).toEqual({
      fieldSize: 0,
      bracketSize: 0,
      seeds: [],
      firstRound: [],
    });
  });

  it("assigns seeds by standings rank", () => {
    const result = seedBracket([
      row(2, "b", "Bears"),
      row(1, "a", "Lakers"),
      row(3, "c", "Eagles"),
    ]);

    expect(result.seeds.map((seed) => seed.teamId)).toEqual([
      "a",
      "b",
      "c",
    ]);

    expect(result.seeds.map((seed) => seed.seed)).toEqual([
      1,
      2,
      3,
    ]);
  });

  it("expands the field to the next power-of-two bracket", () => {
    const result = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
      row(5, "e", "E"),
      row(6, "f", "F"),
    ]);

    expect(result.fieldSize).toBe(6);
    expect(result.bracketSize).toBe(8);
  });

  it("pairs highest against lowest available seed", () => {
    const result = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    expect(result.firstRound[0]).toMatchObject({
      homeSeed: {
        seed: 1,
        teamId: "a",
      },
      awaySeed: {
        seed: 4,
        teamId: "d",
      },
      bye: false,
    });

    expect(result.firstRound[1]).toMatchObject({
      homeSeed: {
        seed: 2,
        teamId: "b",
      },
      awaySeed: {
        seed: 3,
        teamId: "c",
      },
      bye: false,
    });
  });

  it("marks unmatched high seeds as first-round byes", () => {
    const result = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
    ]);

    expect(result.bracketSize).toBe(4);

    expect(result.firstRound[0]).toMatchObject({
      homeSeed: {
        seed: 1,
        teamId: "a",
      },
      awaySeed: null,
      bye: true,
    });

    expect(result.firstRound[1]).toMatchObject({
      homeSeed: {
        seed: 2,
        teamId: "b",
      },
      awaySeed: {
        seed: 3,
        teamId: "c",
      },
      bye: false,
    });
  });

  it("rejects duplicate teams", () => {
    expect(() =>
      seedBracket([
        row(1, "a", "A"),
        row(2, "a", "A duplicate"),
      ]),
    ).toThrow("Duplicate team in standings");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - deterministic bracket seeding engine"
echo "  - seeds derived from standings rank"
echo "  - next-power-of-two bracket sizing"
echo "  - high-vs-low first-round pairing"
echo "  - automatic first-round byes"
echo "  - duplicate-team protection"
echo "  - Milestone 8.4 unit tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 8.5 - Bracket API / UI Integration"
