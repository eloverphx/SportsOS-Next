export const ROLES = {
  SYSTEM_ADMIN: "system_admin",
  ORGANIZATION_OWNER: "organization_owner",
  ORGANIZATION_ADMIN: "organization_admin",
  TEAM_ADMIN: "team_admin",
  COACH: "coach",
  SCOREKEEPER: "scorekeeper",
  BROADCASTER: "broadcaster",
  VIEWER: "viewer",
} as const;

export type Role = (typeof ROLES)[keyof typeof ROLES];

const ROLE_VALUES = new Set<Role>(Object.values(ROLES));

/**
 * Maps values already stored in the database to the canonical SportsOS roles.
 *
 * The current database defaults users to "admin", so that value must remain
 * supported until a later migration updates existing rows.
 */
export function normalizeRole(value: unknown): Role {
  if (typeof value !== "string") {
    return ROLES.VIEWER;
  }

  const normalized = value.trim().toLowerCase();

  if (normalized === "admin") {
    return ROLES.ORGANIZATION_ADMIN;
  }

  if (ROLE_VALUES.has(normalized as Role)) {
    return normalized as Role;
  }

  return ROLES.VIEWER;
}

export function isRole(value: unknown): value is Role {
  return typeof value === "string" && ROLE_VALUES.has(value as Role);
}
