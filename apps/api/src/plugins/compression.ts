import type { FastifyInstance } from 'fastify';
import compress from '@fastify/compress';

export async function registerCompression(
  app: FastifyInstance
): Promise<void> {
  await app.register(compress, {
    global: true,
    threshold: 1024
  });
}
