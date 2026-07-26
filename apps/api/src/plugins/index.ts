import type { FastifyInstance } from 'fastify';
import { registerCompression } from './compression.js';
import { registerCors } from './cors.js';
import { registerErrorHandling } from './errors.js';
import { registerRequestContext } from './request-context.js';
import { registerSecurityPlugins } from './security.js';

export async function registerPlatformPlugins(
  app: FastifyInstance
): Promise<void> {
  await registerRequestContext(app);
  await registerCors(app);
  await registerSecurityPlugins(app);
  await registerCompression(app);
  await registerErrorHandling(app);
}
