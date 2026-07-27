import type { FastifyInstance } from "fastify";

export async function registerRequestContext(app: FastifyInstance): Promise<void> {
  app.addHook("onSend", async (request, reply, payload) => {
    reply.header("x-request-id", request.id);
    return payload;
  });
}
