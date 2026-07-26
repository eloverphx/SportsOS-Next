import type { FastifyInstance } from 'fastify';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';

export async function registerOpenApi(
  app: FastifyInstance
): Promise<void> {
  await app.register(swagger, {
    openapi: {
      info: {
        title: 'SportsOS API',
        description: 'SportsOS platform API',
        version: '0.3.5'
      },
      tags: [
        {
          name: 'Platform',
          description: 'Platform status and metadata'
        }
      ]
    }
  });

  await app.register(swaggerUi, {
    routePrefix: '/docs',
    uiConfig: {
      docExpansion: 'list',
      deepLinking: true
    },
    staticCSP: true
  });
}
