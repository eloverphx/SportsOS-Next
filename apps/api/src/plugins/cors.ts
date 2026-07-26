import type { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import { config } from '@sportsos/config';

export async function registerCors(
  app: FastifyInstance
): Promise<void> {
  await app.register(cors, {
    origin: config.dashboard.origin,
    credentials: true,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Authorization',
      'Content-Type',
      'X-Request-Id'
    ],
    exposedHeaders: [
      'X-Request-Id',
      'X-RateLimit-Limit',
      'X-RateLimit-Remaining',
      'X-RateLimit-Reset',
      'Retry-After'
    ]
  });
}
