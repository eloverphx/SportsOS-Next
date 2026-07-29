import type { Permission } from "./permissions.js";
import type { Role } from "./roles.js";

export interface AuthenticatedUserResponse {
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
  readonly user: AuthenticatedUserResponse;
}

export interface CurrentUserResponse {
  readonly user: AuthenticatedUserResponse;
}
