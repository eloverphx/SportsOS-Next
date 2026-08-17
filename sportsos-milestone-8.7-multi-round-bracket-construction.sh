#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.7-multi-round-bracket-construction"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

SEEDING_LIB="apps/dashboard/lib/tournament-bracket-seeding.ts"
ADVANCE_LIB="apps/dashboard/lib/tournament-bracket-advancement.ts"
MULTI_LIB="apps/dashboard/lib/tournament-bracket-rounds.ts"
MULTI_TEST="apps/dashboard/test/tournament-bracket-rounds-8.7.test.ts"

for file in "$SEEDING_LIB" "$ADVANCE_LIB"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$MULTI_LIB")" \
  "$BACKUP_DIR/$(dirname "$MULTI_TEST")"

for file in "$MULTI_LIB" "$MULTI_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$MULTI_LIB" <<'EOF'
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
EOF

cat > "$MULTI_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  seedBracket,
} from "../lib/tournament-bracket-seeding";
import {
  buildTournamentBracketTree,
} from "../lib/tournament-bracket-rounds";

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

describe("Milestone 8.7 multi-round bracket construction", () => {
  it("builds all rounds for a four-team bracket", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    const tree = buildTournamentBracketTree(
      seeded,
      [],
    );

    expect(tree.rounds).toHaveLength(2);
    expect(tree.rounds[0]?.name).toBe("Semifinals");
    expect(tree.rounds[1]?.name).toBe("Championship");
  });

  it("propagates finalized winners into the championship", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    const firstRound = seeded.firstRound;

    const tree = buildTournamentBracketTree(
      seeded,
      [
        {
          matchupId: firstRound[0]?.id ?? "",
          homeScore: 5,
          awayScore: 1,
          status: "FINAL",
        },
        {
          matchupId: firstRound[1]?.id ?? "",
          homeScore: 2,
          awayScore: 3,
          status: "FINAL",
        },
      ],
    );

    expect(
      tree.rounds[1]?.matchups[0]?.homeSeed?.teamId,
    ).toBe("a");

    expect(
      tree.rounds[1]?.matchups[0]?.awaySeed?.teamId,
    ).toBe("c");
  });

  it("keeps unresolved next-round slots as TBD", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    const tree = buildTournamentBracketTree(
      seeded,
      [],
    );

    expect(
      tree.rounds[1]?.matchups[0]?.homeSeed,
    ).toBeNull();

    expect(
      tree.rounds[1]?.matchups[0]?.awaySeed,
    ).toBeNull();
  });

  it("propagates byes through the next round", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
    ]);

    const tree = buildTournamentBracketTree(
      seeded,
      [],
    );

    expect(
      tree.rounds[1]?.matchups[0]?.homeSeed?.teamId,
    ).toBe("a");
  });

  it("resolves a champion once the final is complete", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
    ]);

    const final = seeded.firstRound[0];

    if (!final) {
      throw new Error("Expected championship matchup.");
    }

    const tree = buildTournamentBracketTree(
      seeded,
      [
        {
          matchupId: final.id,
          homeScore: 4,
          awayScore: 2,
          status: "FINAL",
        },
      ],
    );

    expect(tree.rounds).toHaveLength(1);
    expect(tree.rounds[0]?.name).toBe("Championship");
    expect(tree.champion?.teamId).toBe("a");
  });

  it("returns an empty tree for an empty field", () => {
    const tree = buildTournamentBracketTree(
      seedBracket([]),
      [],
    );

    expect(tree).toEqual({
      fieldSize: 0,
      bracketSize: 0,
      rounds: [],
      champion: null,
    });
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - full multi-round bracket tree"
echo "  - automatic round naming"
echo "  - winner propagation through every round"
echo "  - TBD preservation for unresolved slots"
echo "  - bye propagation"
echo "  - champion resolution"
echo "  - Milestone 8.7 unit tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 8.8 - Multi-Round Bracket UI"
