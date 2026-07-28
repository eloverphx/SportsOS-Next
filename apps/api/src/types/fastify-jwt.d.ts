import "@fastify/jwt";
import type { IdentityTokenPayload } from "../modules/auth/index.js";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: IdentityTokenPayload;
    user: IdentityTokenPayload;
  }
}
