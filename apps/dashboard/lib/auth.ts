export const AUTH_TOKEN_KEY = "sportsos_token";
export const AUTH_USER_KEY = "sportsos_user";

export const PERMISSIONS = {
  ORGANIZATION_READ: "organization.read",
  ORGANIZATION_CREATE: "organization.create",
  ORGANIZATION_UPDATE: "organization.update",
  ORGANIZATION_DELETE: "organization.delete",
  ORGANIZATION_MEMBERS_MANAGE: "organization.members.manage",

  TEAM_READ: "team.read",
  TEAM_CREATE: "team.create",
  TEAM_UPDATE: "team.update",
  TEAM_DELETE: "team.delete",
  TEAM_ROSTER_MANAGE: "team.roster.manage",

  PLAYER_READ: "player.read",
  PLAYER_MANAGE: "player.manage",

  SEASON_READ: "season.read",
  SEASON_MANAGE: "season.manage",

  GAME_READ: "game.read",
  GAME_MANAGE: "game.manage",
  GAME_SCORE: "game.score",

  STREAM_READ: "stream.read",
  STREAM_MANAGE: "stream.manage",

  SCOREBOARD_READ: "scoreboard.read",
  SCOREBOARD_MANAGE: "scoreboard.manage",

  SYSTEM_READ: "system.read",
  SYSTEM_MANAGE: "system.manage",
} as const;

export type Permission = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

export type Role =
  | "system_admin"
  | "organization_owner"
  | "organization_admin"
  | "team_admin"
  | "coach"
  | "scorekeeper"
  | "broadcaster"
  | "viewer";

export interface AuthenticatedUser {
  readonly id: number;
  readonly organizationId: number;
  readonly organizationName: string;
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly username: string;
  readonly role: Role;
  readonly permissions: readonly Permission[];
}

export interface LoginResponse {
  readonly token: string;
  readonly user: AuthenticatedUser;
}

export interface CurrentUserResponse {
  readonly user: AuthenticatedUser;
}

export function getStoredToken(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  return window.localStorage.getItem(AUTH_TOKEN_KEY);
}

export function getStoredUser(): AuthenticatedUser | null {
  if (typeof window === "undefined") {
    return null;
  }

  const serializedUser = window.localStorage.getItem(AUTH_USER_KEY);

  if (!serializedUser) {
    return null;
  }

  try {
    return JSON.parse(serializedUser) as AuthenticatedUser;
  } catch {
    window.localStorage.removeItem(AUTH_USER_KEY);
    return null;
  }
}

export function storeAuthentication(token: string, user: AuthenticatedUser): void {
  window.localStorage.setItem(AUTH_TOKEN_KEY, token);
  window.localStorage.setItem(AUTH_USER_KEY, JSON.stringify(user));
}

export function clearAuthentication(): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.removeItem(AUTH_TOKEN_KEY);
  window.localStorage.removeItem(AUTH_USER_KEY);
}

export function userHasPermission(user: AuthenticatedUser | null, permission: Permission): boolean {
  return user?.permissions.includes(permission) ?? false;
}
