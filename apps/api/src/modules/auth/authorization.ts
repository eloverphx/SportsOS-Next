import type { FastifyRequest } from "fastify";
import { AuthorizationError } from "./authorization-error.js";
import { authenticatedIdentity } from "./identity.js";
import {
  roleHasPermission,
  type Permission,
} from "./permissions.js";
import { ROLES } from "./roles.js";
import type { AuthenticatedIdentity } from "./types.js";

export interface PermissionRequirement {
  readonly permission: Permission;
  readonly organizationId?: number;
}

export function assertPermission(
  identity: AuthenticatedIdentity,
  requirement: PermissionRequirement,
): void {
  if (!roleHasPermission(identity.role, requirement.permission)) {
    throw new AuthorizationError();
  }

  if (
    requirement.organizationId !== undefined &&
    identity.role !== ROLES.SYSTEM_ADMIN &&
    identity.organizationId !== requirement.organizationId
  ) {
    throw new AuthorizationError(
      "You do not have access to this organization",
    );
  }
}

export async function requirePermission(
  request: FastifyRequest,
  requirement: PermissionRequirement,
): Promise<AuthenticatedIdentity> {
  await request.jwtVerify();

  const identity = authenticatedIdentity(request);

  assertPermission(identity, requirement);

  return identity;
}
