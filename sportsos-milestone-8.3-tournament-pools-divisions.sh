#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.3-tournament-pools-divisions"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

STANDINGS_LIB="apps/dashboard/lib/tournament-standings.ts"
GROUP_LIB="apps/dashboard/lib/tournament-pools.ts"
GROUP_TEST="apps/dashboard/test/tournament-pools-8.3.test.ts"
ROUTE="apps/dashboard/app/api/tournament/standings/route.ts"
COMPONENT="apps/dashboard/components/tournament/TournamentStandingsTable.tsx"

for file in "$STANDINGS_LIB" "$ROUTE" "$COMPONENT"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$GROUP_LIB")" \
  "$BACKUP_DIR/$(dirname "$GROUP_TEST")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$COMPONENT")"

for file in "$GROUP_LIB" "$GROUP_TEST" "$ROUTE" "$COMPONENT"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$GROUP_LIB" <<'EOF'
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
EOF

cat > "$GROUP_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  buildTournamentPoolStandings,
  deriveDefaultPools,
} from "../lib/tournament-pools";

describe("Milestone 8.3 tournament pools / divisions", () => {
  const teams = [
    { id: "a", name: "Lakers" },
    { id: "b", name: "Bears" },
    { id: "c", name: "Eagles" },
    { id: "d", name: "Wolves" },
  ];

  it("derives a default all-teams pool", () => {
    expect(deriveDefaultPools(teams)).toEqual([
      {
        id: "all",
        name: "All Teams",
        teamIds: ["a", "b", "c", "d"],
      },
    ]);
  });

  it("builds standings independently per pool", () => {
    const pools = [
      {
        id: "pool-a",
        name: "Pool A",
        teamIds: ["a", "b"],
      },
      {
        id: "pool-b",
        name: "Pool B",
        teamIds: ["c", "d"],
      },
    ];

    const games = [
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
        homeTeamId: "c",
        awayTeamId: "d",
        homeScore: 2,
        awayScore: 4,
        status: "FINAL",
      },
      {
        id: "cross",
        homeTeamId: "a",
        awayTeamId: "c",
        homeScore: 9,
        awayScore: 0,
        status: "FINAL",
      },
    ];

    const result = buildTournamentPoolStandings(
      pools,
      teams,
      games,
    );

    expect(result).toHaveLength(2);
    expect(result[0]?.standings[0]?.teamId).toBe("a");
    expect(result[1]?.standings[0]?.teamId).toBe("d");

    expect(
      result[0]?.standings.find(
        (row) => row.teamId === "a",
      )?.gamesPlayed,
    ).toBe(1);
  });

  it("ignores unknown team ids inside a pool", () => {
    const result = buildTournamentPoolStandings(
      [
        {
          id: "pool-a",
          name: "Pool A",
          teamIds: ["a", "missing"],
        },
      ],
      teams,
      [],
    );

    expect(result[0]?.standings).toHaveLength(1);
    expect(result[0]?.standings[0]?.teamId).toBe("a");
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file = "apps/dashboard/app/api/tournament/standings/route.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes('from "../../../../lib/tournament-pools"')) {
  text = text.replace(
`import {
  buildTournamentStandings,
  type TournamentStandingGame,
  type TournamentStandingTeam,
} from "../../../../lib/tournament-standings";`,
`import {
  buildTournamentStandings,
  type TournamentStandingGame,
  type TournamentStandingTeam,
} from "../../../../lib/tournament-standings";
import {
  buildTournamentPoolStandings,
  deriveDefaultPools,
} from "../../../../lib/tournament-pools";`,
  );
}

if (!text.includes("const pools = deriveDefaultPools(teams);")) {
  text = text.replace(
`  const teams = [...teamsById.values()];
  const games = normalized.map((item) => item.game);

  return NextResponse.json({
    teams,
    games,
    standings: buildTournamentStandings(teams, games),
  });`,
`  const teams = [...teamsById.values()];
  const games = normalized.map((item) => item.game);
  const pools = deriveDefaultPools(teams);

  return NextResponse.json({
    teams,
    games,
    pools,
    standings: buildTournamentStandings(teams, games),
    poolStandings: buildTournamentPoolStandings(
      pools,
      teams,
      games,
    ),
  });`,
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentStandingsTable.tsx";

let text = fs.readFileSync(file, "utf8");

text = text.replace(
`type StandingsResponse = {
  standings?: TournamentStandingRow[];
  error?: string;
};`,
`type PoolStandingsResponse = {
  poolId: string;
  poolName: string;
  standings: TournamentStandingRow[];
};

type StandingsResponse = {
  standings?: TournamentStandingRow[];
  poolStandings?: PoolStandingsResponse[];
  error?: string;
};`,
);

if (!text.includes("const [poolRows")) {
  text = text.replace(
`  const [rows, setRows] = useState<TournamentStandingRow[]>([]);
  const [loading, setLoading] = useState(true);`,
`  const [rows, setRows] = useState<TournamentStandingRow[]>([]);
  const [poolRows, setPoolRows] =
    useState<PoolStandingsResponse[]>([]);
  const [loading, setLoading] = useState(true);`,
  );
}

if (!text.includes("setPoolRows(payload.poolStandings ?? []);")) {
  text = text.replace(
`        if (active) {
          setRows(payload.standings ?? []);
        }`,
`        if (active) {
          setRows(payload.standings ?? []);
          setPoolRows(payload.poolStandings ?? []);
        }`,
  );
}

if (!text.includes("data-testid=\"tournament-pool-standings\"")) {
  text = text.replace(
`      {rows.length === 0 ? (`,
`      {poolRows.length > 1 ? (
        <div
          data-testid="tournament-pool-standings"
          className="border-b border-slate-800 px-5 py-4"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Pools / divisions
          </div>

          <div className="mt-3 flex flex-wrap gap-2">
            {poolRows.map((pool) => (
              <span
                key={pool.poolId}
                className="rounded-full border border-slate-700 px-3 py-1 text-xs font-semibold text-slate-300"
              >
                {pool.poolName}: {pool.standings.length} teams
              </span>
            ))}
          </div>
        </div>
      ) : null}

      {rows.length === 0 ? (`,
  );
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - reusable tournament pool/division model"
echo "  - pool-specific standings using the shared 8.1 engine"
echo "  - cross-pool games excluded from pool standings"
echo "  - default All Teams pool"
echo "  - standings API now returns pools + poolStandings"
echo "  - Milestone 8.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build && \\"
echo "  docker compose up -d --build dashboard && \\"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 8.4 - Bracket Seeding Engine"
