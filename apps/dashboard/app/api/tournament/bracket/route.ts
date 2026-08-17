import { NextResponse } from "next/server";
import {
  seedBracket,
} from "../../../../lib/tournament-bracket-seeding";
import {
  buildTournamentBracketTree,
} from "../../../../lib/tournament-bracket-rounds";
import type {
  BracketMatchupResult,
} from "../../../../lib/tournament-bracket-advancement";
import type {
  TournamentStandingRow,
} from "../../../../lib/tournament-standings";

const SITE_BASE_URL =
  process.env.SPORTSOS_DASHBOARD_URL ??
  process.env.NEXT_PUBLIC_SITE_URL ??
  "http://localhost:4000";

type StandingsPayload = {
  standings?: TournamentStandingRow[];
  error?: string;
};

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord | null {
  return value && typeof value === "object"
    ? (value as UnknownRecord)
    : null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : 0;
}

function normalizeBracketResults(
  payload: unknown,
): BracketMatchupResult[] {
  const root = record(payload);

  if (!root) {
    return [];
  }

  const candidates = Array.isArray(root.results)
    ? root.results
    : Array.isArray(record(root.data)?.results)
      ? (record(root.data)?.results as unknown[])
      : [];

  return candidates
    .map((value) => {
      const item = record(value);

      if (!item) {
        return null;
      }

      const matchupId =
        stringValue(item.matchupId) ||
        stringValue(item.id);

      if (!matchupId) {
        return null;
      }

      return {
        matchupId,
        homeScore: numberValue(item.homeScore),
        awayScore: numberValue(item.awayScore),
        status: stringValue(item.status),
      };
    })
    .filter(
      (
        value,
      ): value is BracketMatchupResult =>
        value !== null,
    );
}

export async function GET() {
  const standingsResponse = await fetch(
    `${SITE_BASE_URL}/api/tournament/standings`,
    {
      cache: "no-store",
    },
  ).catch(() => null);

  if (!standingsResponse || !standingsResponse.ok) {
    return NextResponse.json(
      {
        error: "Unable to load tournament standings for bracket seeding.",
      },
      {
        status: 502,
      },
    );
  }

  const standingsPayload =
    (await standingsResponse.json()) as StandingsPayload;

  const standings = standingsPayload.standings ?? [];
  const seeded = seedBracket(standings);

  const resultsResponse = await fetch(
    `${SITE_BASE_URL}/api/tournament/bracket/results`,
    {
      cache: "no-store",
    },
  ).catch(() => null);

  let results: BracketMatchupResult[] = [];

  if (resultsResponse?.ok) {
    results = normalizeBracketResults(
      await resultsResponse.json(),
    );
  }

  const tree = buildTournamentBracketTree(
    seeded,
    results,
  );

  return NextResponse.json({
    standings,
    bracket: seeded,
    results,
    tree,
  });
}
