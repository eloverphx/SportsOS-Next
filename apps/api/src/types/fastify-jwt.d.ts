import "@fastify/jwt";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: {
      sub: string;
      organizationId: number;
      role: string;
    };

    user: {
      sub: string;
      organizationId: number;
      role: string;
    };
  }
}
