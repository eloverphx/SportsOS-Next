import {
  clearAuthentication,
  getStoredRefreshToken,
  storeAuthentication,
  type LoginResponse,
} from "./auth";
import { getApiUrl } from "./api-url";

let refreshPromise: Promise<string> | null = null;

async function rotateSession(): Promise<string> {
  const refreshToken = getStoredRefreshToken();

  if (!refreshToken) {
    clearAuthentication();
    throw new Error("Authentication is required");
  }

  let response: Response;

  try {
    response = await fetch(`${getApiUrl()}/auth/refresh`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ refreshToken }),
    });
  } catch {
    throw new Error("Could not connect to the SportsOS API");
  }

  const body = (await response.json().catch(() => ({}))) as Partial<LoginResponse> & {
    readonly error?: string;
  };

  if (!response.ok || !body.token || !body.refreshToken || !body.user) {
    clearAuthentication();

    throw new Error(
      typeof body.error === "string" && body.error.trim()
        ? body.error
        : "Your session has expired. Sign in again.",
    );
  }

  storeAuthentication(body.token, body.refreshToken, body.user);

  return body.token;
}

export async function refreshAuthentication(): Promise<string> {
  if (!refreshPromise) {
    refreshPromise = rotateSession().finally(() => {
      refreshPromise = null;
    });
  }

  return refreshPromise;
}
