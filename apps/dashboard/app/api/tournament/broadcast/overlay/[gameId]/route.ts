import { NextRequest, NextResponse } from "next/server";
import {
  normalizeBroadcastOverlaySnapshot,
} from "../../../../../../lib/broadcast-overlay-contract";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

export async function GET(
  request: NextRequest,
  context: {
    params: Promise<{
      gameId: string;
    }>;
  },
) {
  const { gameId } = await context.params;

  const headers = new Headers({
    accept: "application/json",
  });

  const authorization =
    request.headers.get("authorization");
  const cookie = request.headers.get("cookie");

  if (authorization) {
    headers.set("authorization", authorization);
  }

  if (cookie) {
    headers.set("cookie", cookie);
  }

  const response = await fetch(
    `${API_BASE_URL}/games/${encodeURIComponent(gameId)}`,
    {
      cache: "no-store",
      headers,
    },
  );

  if (!response.ok) {
    return NextResponse.json(
      {
        error: "Unable to load authoritative game for overlay.",
        upstreamStatus: response.status,
      },
      {
        status: response.status === 404 ? 404 : 502,
      },
    );
  }

  const payload = (await response.json()) as unknown;

  const game =
    payload &&
    typeof payload === "object" &&
    "game" in payload
      ? (payload as { game: unknown }).game
      : payload;

  try {
    return NextResponse.json(
      normalizeBroadcastOverlaySnapshot(game),
      {
        headers: {
          "cache-control": "no-store",
        },
      },
    );
  } catch (cause) {
    return NextResponse.json(
      {
        error:
          cause instanceof Error
            ? cause.message
            : "Unable to normalize broadcast overlay payload.",
      },
      {
        status: 500,
      },
    );
  }
}
