#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.6-bracket-advancement-winner-propagation"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

SEEDING_LIB="apps/dashboard/lib/tournament-bracket-seeding.ts"
ADVANCE_LIB="apps/dashboard/lib/tournament-bracket-advancement.ts"
ADVANCE_TEST="apps/dashboard/test/tournament-bracket-advancement-8.6.test.ts"

[[ -f "$SEEDING_LIB" ]] || {
  echo "ERROR: Milestone 8.4 bracket seeding engine missing: $SEEDING_LIB" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$ADVANCE_LIB")" \
  "$BACKUP_DIR/$(dirname "$ADVANCE_TEST")"

for file in "$ADVANCE_LIB" "$ADVANCE_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$ADVANCE_LIB" <<'EOF'
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
EOF

cat > "$ADVANCE_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  advanceBracketRound,
} from "../lib/tournament-bracket-advancement";
import type {
  BracketMatchup,
  BracketSeed,
} from "../lib/tournament-bracket-seeding";

function seed(
  seedNumber: number,
  teamId: string,
  teamName: string,
): BracketSeed {
  return {
    seed: seedNumber,
    teamId,
    teamName,
  };
}

function matchup(
  id: string,
  slot: number,
  homeSeed: BracketSeed | null,
  awaySeed: BracketSeed | null,
  bye = false,
): BracketMatchup {
  return {
    id,
    round: 1,
    slot,
    homeSeed,
    awaySeed,
    bye,
  };
}

describe("Milestone 8.6 bracket advancement / winner propagation", () => {
  it("advances a finalized home winner", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        seed(4, "d", "D"),
      ),
      matchup(
        "m2",
        2,
        seed(2, "b", "B"),
        seed(3, "c", "C"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m1",
        homeScore: 5,
        awayScore: 2,
        status: "FINAL",
      },
      {
        matchupId: "m2",
        homeScore: 1,
        awayScore: 4,
        status: "FINAL",
      },
    ]);

    expect(result.resolvedRound[0]?.winner?.teamId).toBe("a");
    expect(result.resolvedRound[1]?.winner?.teamId).toBe("c");

    expect(result.nextRound[0]).toMatchObject({
      round: 2,
      slot: 1,
      homeSeed: {
        teamId: "a",
      },
      awaySeed: {
        teamId: "c",
      },
    });
  });

  it("automatically advances a bye", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        null,
        true,
      ),
      matchup(
        "m2",
        2,
        seed(2, "b", "B"),
        seed(3, "c", "C"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m2",
        homeScore: 2,
        awayScore: 1,
        status: "FINAL",
      },
    ]);

    expect(result.resolvedRound[0]?.winner?.teamId).toBe("a");

    expect(result.nextRound[0]).toMatchObject({
      homeSeed: {
        teamId: "a",
      },
      awaySeed: {
        teamId: "b",
      },
    });
  });

  it("does not advance an unfinished matchup", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        seed(4, "d", "D"),
      ),
      matchup(
        "m2",
        2,
        seed(2, "b", "B"),
        seed(3, "c", "C"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m1",
        homeScore: 3,
        awayScore: 2,
        status: "LIVE",
      },
    ]);

    expect(result.resolvedRound[0]?.winner).toBeNull();
    expect(result.nextRound[0]?.homeSeed).toBeNull();
  });

  it("does not choose a winner for a tied final", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        seed(4, "d", "D"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m1",
        homeScore: 2,
        awayScore: 2,
        status: "FINAL",
      },
    ]);

    expect(result.resolvedRound[0]?.winner).toBeNull();
  });

  it("rejects invalid finalized scores", () => {
    expect(() =>
      advanceBracketRound(
        [
          matchup(
            "m1",
            1,
            seed(1, "a", "A"),
            seed(4, "d", "D"),
          ),
        ],
        [
          {
            matchupId: "m1",
            homeScore: Number.NaN,
            awayScore: 2,
            status: "FINAL",
          },
        ],
      ),
    ).toThrow("Invalid score for matchup m1.");
  });

  it("returns no next round when resolving a championship matchup", () => {
    const result = advanceBracketRound(
      [
        matchup(
          "championship",
          1,
          seed(1, "a", "A"),
          seed(2, "b", "B"),
        ),
      ],
      [
        {
          matchupId: "championship",
          homeScore: 4,
          awayScore: 3,
          status: "FINAL",
        },
      ],
    );

    expect(result.nextRound).toEqual([]);
    expect(result.resolvedRound[0]?.winner?.teamId).toBe("a");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - pure bracket advancement engine"
echo "  - finalized-result winner resolution"
echo "  - automatic bye advancement"
echo "  - next-round winner propagation"
echo "  - unfinished/tied games do not advance"
echo "  - invalid-score protection"
echo "  - championship terminal handling"
echo "  - Milestone 8.6 unit tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 8.7 - Multi-Round Bracket Construction"
