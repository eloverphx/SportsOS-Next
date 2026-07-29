import { clearAuthentication, getStoredToken } from "./auth";
import { getApiUrl } from "./api-url";

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

export async function authenticatedFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = getStoredToken();

  if (!token) {
    throw new ApiError("Authentication is required", 401);
  }

  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);

  if (init.body !== undefined && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(`${getApiUrl()}${path}`, {
    ...init,
    headers,
  });

  if (response.status === 401) {
    clearAuthentication();
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
