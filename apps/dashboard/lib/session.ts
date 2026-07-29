import { authenticatedFetch } from "./authenticated-api";
import { AUTH_USER_KEY, type AuthenticatedUser, type CurrentUserResponse } from "./auth";

export async function refreshCurrentUser(): Promise<AuthenticatedUser> {
  const response = await authenticatedFetch<CurrentUserResponse>("/auth/me");

  window.localStorage.setItem(AUTH_USER_KEY, JSON.stringify(response.user));

  return response.user;
}
