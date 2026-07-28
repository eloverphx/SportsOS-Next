import type { FastifyRequest } from "fastify";
import { permissionsForRole } from "./permissions.js";
import { normalizeRole } from "./roles.js";
import type {
  AuthenticatedIdentity,
  IdentityTokenPayload,
} from "./types.js";

export function identityFromToken(
  payload: IdentityTokenPayload,
): AuthenticatedIdentity {
  const role = normalizeRole(payload.role);
  const userId = Number(payload.sub);

  if (!Number.isSafeInteger(userId) || userId <= 0) {
    throw new Error("Authenticated user identifier is invalid");
  }

  if (
    !Number.isSafeInteger(payload.organizationId) ||
    payload.organizationId <= 0
  ) {
    throw new Error("Authenticated organization identifier is invalid");
  }

  return {
    sub: payload.sub,
    userId,
    organizationId: payload.organizationId,
    role,
    permissions: permissionsForRole(role),
  };
}

export function authenticatedIdentity(
  request: FastifyRequest,
): AuthenticatedIdentity {
  return identityFromToken(request.user as IdentityTokenPayload);
}
