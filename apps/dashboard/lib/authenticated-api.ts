import { getStoredToken } from "./auth";
import { getApiUrl } from "./api-url";
import { refreshAuthentication } from "./session-refresh";

export class ApiError extends Error {
  public readonly status: number;
  public readonly code?: string;

  public constructor(message: string, status: number, code?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

interface ApiErrorBody {
  readonly error?:
    | string
    | {
        readonly code?: string;
        readonly message?: string;
      };
}

function readError(body: ApiErrorBody): {
  readonly message: string;
  readonly code?: string;
} {
  if (typeof body.error === "string") {
    return {
      message: body.error,
    };
  }

  return {
    message: body.error?.message ?? "API request failed",
    code: body.error?.code,
  };
}

function requestHeaders(init: RequestInit, accessToken: string): Headers {
  const headers = new Headers(init.headers);

  headers.set("Authorization", `Bearer ${accessToken}`);

  if (init.body !== undefined && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  return headers;
}

async function request(path: string, init: RequestInit, accessToken: string): Promise<Response> {
  return await fetch(`${getApiUrl()}${path}`, {
    ...init,
    headers: requestHeaders(init, accessToken),
  });
}

export async function authenticatedFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const initialToken = getStoredToken();

  if (!initialToken) {
    throw new ApiError("Authentication is required", 401);
  }

  let response: Response;

  try {
    response = await request(path, init, initialToken);

    if (response.status === 401) {
      const refreshedToken = await refreshAuthentication();
      response = await request(path, init, refreshedToken);
    }
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }

    throw new ApiError(
      error instanceof Error ? error.message : "Could not connect to the SportsOS API",
      0,
    );
  }

  if (!response.ok) {
    let body: ApiErrorBody = {};

    try {
      body = (await response.json()) as ApiErrorBody;
    } catch {
      // The response may be empty or non-JSON.
    }

    const error = readError(body);

    throw new ApiError(error.message, response.status, error.code);
  }

  return (await response.json()) as T;
}
