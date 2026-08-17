import { NextRequest, NextResponse } from "next/server";
import {
  buildBroadcastSessionSummary,
  type BroadcastOverlayState,
  type BroadcastTransportState,
} from "../../../../../lib/tournament-broadcast-session";

function boolParam(
  request: NextRequest,
  key: string,
): boolean {
  return request.nextUrl.searchParams.get(key) === "true";
}

function transportParam(
  request: NextRequest,
): BroadcastTransportState {
  const value =
    request.nextUrl.searchParams.get("transport")?.toUpperCase();

  if (
    value === "OFFLINE" ||
    value === "CONNECTING" ||
    value === "READY" ||
    value === "LIVE" ||
    value === "ERROR"
  ) {
    return value;
  }

  return "OFFLINE";
}

function overlayParam(
  request: NextRequest,
): BroadcastOverlayState {
  const value =
    request.nextUrl.searchParams.get("overlay")?.toUpperCase();

  if (
    value === "DISABLED" ||
    value === "READY" ||
    value === "ACTIVE"
  ) {
    return value;
  }

  return "DISABLED";
}

export async function GET(request: NextRequest) {
  const gameId =
    request.nextUrl.searchParams.get("gameId")?.trim() ?? "";

  if (!gameId) {
    return NextResponse.json(
      {
        error: "gameId is required.",
      },
      {
        status: 400,
      },
    );
  }

  const summary = buildBroadcastSessionSummary({
    gameId,
    operatorAssigned: boolParam(
      request,
      "operatorAssigned",
    ),
    gameAuthorized: boolParam(
      request,
      "gameAuthorized",
    ),
    gameLive: boolParam(request, "gameLive"),
    transportState: transportParam(request),
    overlayState: overlayParam(request),
    streamKeyConfigured: boolParam(
      request,
      "streamKeyConfigured",
    ),
  });

  return NextResponse.json({
    summary,
  });
}
