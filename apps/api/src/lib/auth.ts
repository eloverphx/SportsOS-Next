import type { FastifyRequest } from "fastify";
import {
  authenticatedIdentity,
  type AuthenticatedIdentity,
} from "../modules/auth/index.js";

export type AuthUser = AuthenticatedIdentity;

export async function requireAuth(
  request: FastifyRequest,
): Promise<void> {
  await request.jwtVerify();
}

export function authUser(
  request: FastifyRequest,
): AuthenticatedIdentity {
  return authenticatedIdentity(request);
}
