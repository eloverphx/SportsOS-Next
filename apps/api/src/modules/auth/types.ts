import type { Permission } from "./permissions.js";
import type { Role } from "./roles.js";

export interface AuthenticatedIdentity {
  /**
   * JWT subject. Retained as a string because Fastify JWT uses `sub`.
   */
  readonly sub: string;

  readonly userId: number;
  readonly organizationId: number;
  readonly role: Role;
  readonly permissions: readonly Permission[];
}

export interface IdentityTokenPayload {
  readonly sub: string;
  readonly organizationId: number;
  readonly role: Role;
}
