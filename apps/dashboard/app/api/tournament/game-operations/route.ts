import { NextResponse } from "next/server";

function apiBaseUrl(): string {
  return (
    process.env.SPORTSOS_API_URL ??
    process.env.API_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://api:4001"
  ).replace(/\/+$/, "");
}

export async function GET() {
  const upstream = new URL("/games", apiBaseUrl());
  upstream.searchParams.set("limit", "100");

  try {
    const response = await fetch(upstream, {
      cache: "no-store",
      headers: {
        accept: "application/json",
      },
    });

    const text = await response.text();

    return new NextResponse(text, {
      status: response.status,
      headers: {
        "content-type":
          response.headers.get("content-type") ?? "application/json",
      },
    });
  } catch (error) {
    return NextResponse.json(
      {
        success: false,
        error: "GAME_OPERATIONS_UPSTREAM_UNAVAILABLE",
        message:
          error instanceof Error
            ? error.message
            : "Unable to reach the SportsOS API.",
      },
      { status: 502 },
    );
  }
}
