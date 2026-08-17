import { NextRequest, NextResponse } from "next/server";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ gameId: string }> },
) {
  const { gameId } = await context.params;

  const headers = new Headers({
    "content-type": "application/json",
  });

  const authorization = request.headers.get("authorization");
  const cookie = request.headers.get("cookie");
  const requestId = request.headers.get("x-request-id");

  if (authorization) headers.set("authorization", authorization);
  if (cookie) headers.set("cookie", cookie);
  if (requestId) headers.set("x-request-id", requestId);

  /*
   * Security boundary:
   * - Forward the user's existing auth context to the real API lifecycle route.
   * - Never send browser testing-override/localStorage state as authority.
   * - The API decides permission and whether startGame is valid.
   */
  const response = await fetch(
    `${API_BASE_URL}/games/${encodeURIComponent(gameId)}/lifecycle`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        command: "startGame",
      }),
      cache: "no-store",
    },
  );

  const contentType =
    response.headers.get("content-type") ?? "application/json";

  const body = await response.text();

  return new NextResponse(body, {
    status: response.status,
    headers: {
      "content-type": contentType,
    },
  });
}
