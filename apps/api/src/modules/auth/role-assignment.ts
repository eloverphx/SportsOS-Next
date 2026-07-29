import { AuthorizationError } from "./authorization-error.js";
import { ROLES, type Role } from "./roles.js";
import type { AuthenticatedIdentity } from "./types.js";

export const ORGANIZATION_MEMBER_ROLES = [
  ROLES.ORGANIZATION_OWNER,
  ROLES.ORGANIZATION_ADMIN,
  ROLES.TEAM_ADMIN,
  ROLES.COACH,
  ROLES.SCOREKEEPER,
  ROLES.BROADCASTER,
  ROLES.VIEWER,
] as const;

export type OrganizationMemberRole = (typeof ORGANIZATION_MEMBER_ROLES)[number];

export function isOrganizationMemberRole(role: Role): role is OrganizationMemberRole {
  return ORGANIZATION_MEMBER_ROLES.includes(role as OrganizationMemberRole);
}

export function assertRoleAssignmentAllowed(
  actor: AuthenticatedIdentity,
  requestedRole: Role,
): void {
  if (actor.role === ROLES.SYSTEM_ADMIN) {
    return;
  }

  if (requestedRole === ROLES.SYSTEM_ADMIN) {
    throw new AuthorizationError(
      "Only a system administrator can assign the system administrator role",
    );
  }

  if (requestedRole === ROLES.ORGANIZATION_OWNER) {
    throw new AuthorizationError(
      "Only a system administrator can assign the organization owner role",
    );
  }

  if (!isOrganizationMemberRole(requestedRole)) {
    throw new AuthorizationError("The requested role cannot be assigned to an organization member");
  }
}
