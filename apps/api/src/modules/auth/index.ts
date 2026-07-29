export {
  AuthorizationError,
} from "./authorization-error.js";

export {
  assertPermission,
  requirePermission,
  type PermissionRequirement,
} from "./authorization.js";

export {
  authenticatedIdentity,
  identityFromToken,
} from "./identity.js";

export {
  PERMISSIONS,
  ROLE_PERMISSIONS,
  permissionsForRole,
  roleHasPermission,
  type Permission,
} from "./permissions.js";

export {
  ROLES,
  isRole,
  normalizeRole,
  type Role,
} from "./roles.js";

export type {
  AuthenticatedIdentity,
  IdentityTokenPayload,
} from "./types.js";
