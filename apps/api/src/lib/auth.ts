import type { FastifyRequest } from 'fastify';

export interface AuthUser {
  sub: string;
  organizationId: number;
  role: string;
}

export async function requireAuth(request: FastifyRequest): Promise<void> {
  await request.jwtVerify();
}

export function authUser(request: FastifyRequest): AuthUser {
  return request.user as AuthUser;
}
