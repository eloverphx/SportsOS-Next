import type { FastifyRequest } from "fastify";
import { authenticatedIdentity, type AuthenticatedIdentity } from "../modules/auth/index.js";
import { assertActiveAccount } from "../modules/auth/account-status.js";

export type AuthUser = AuthenticatedIdentity;

export async function requireAuth(request: FastifyRequest): Promise<void> {
  await request.jwtVerify();
  await assertActiveAccount(authenticatedIdentity(request));
}

export function authUser(request: FastifyRequest): AuthenticatedIdentity {
  return authenticatedIdentity(request);
}
