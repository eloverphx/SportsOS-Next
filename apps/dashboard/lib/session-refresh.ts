import {
  clearAuthentication,
  getStoredRefreshToken,
  storeAuthentication,
  type LoginResponse,
} from "./auth";
import { getApiUrl } from "./api-url";

let refreshPromise: Promise<string> | null = null;

export class SessionRefreshError extends Error {
  public readonly status: number;

  public constructor(message: string, status: number) {
    super(message);
    this.name = "SessionRefreshError";
    this.status = status;
  }
}

async function rotateSession(): Promise<string> {
  const refreshToken = getStoredRefreshToken();

  if (!refreshToken) {
    clearAuthentication();
    throw new SessionRefreshError("Authentication is required", 401);
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
    throw new SessionRefreshError("Could not connect to the SportsOS API", 0);
  }

  const body = (await response.json().catch(() => ({}))) as Partial<LoginResponse> & {
    readonly error?: string;
  };

  if (!response.ok || !body.token || !body.refreshToken || !body.user) {
    const message =
      typeof body.error === "string" && body.error.trim()
        ? body.error
        : response.ok
          ? "The session refresh response was incomplete."
          : "Your session could not be refreshed.";

    const confirmedAuthenticationFailure =
      response.status === 400 || response.status === 401 || response.status === 403;

    if (confirmedAuthenticationFailure) {
      clearAuthentication();

      throw new SessionRefreshError(
        message || "Your session has expired. Sign in again.",
        response.status,
      );
    }

    /*
     * A server outage, proxy failure, or malformed successful response is
     * not proof that the session is invalid. Preserve local credentials.
     */
    throw new SessionRefreshError(
      message || "SportsOS is temporarily unavailable.",
      response.ok ? 502 : response.status,
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
