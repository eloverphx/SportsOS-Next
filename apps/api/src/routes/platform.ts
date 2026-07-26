import type { FastifyInstance } from 'fastify';
import { config } from '@sportsos/config';

const startedAt = Date.now();

export async function platformRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    '/',
    {
      schema: {
        tags: ['Platform'],
        summary: 'API information',
        response: {
          200: {
            type: 'object',
            properties: {
              success: { type: 'boolean' },
              requestId: { type: 'string' },
              data: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  version: { type: 'string' },
                  environment: { type: 'string' },
                  documentation: { type: 'string' }
                }
              }
            }
          }
        }
      }
    },
    async (request) => ({
      success: true,
      requestId: request.id,
      data: {
        name: 'SportsOS API',
        version: '0.3.5',
        environment: config.environment.name,
        documentation: '/docs'
      }
    })
  );

  app.get(
    '/ready',
    {
      schema: {
        tags: ['Platform'],
        summary: 'Application readiness'
      }
    },
    async (request) => ({
      success: true,
      requestId: request.id,
      data: {
        status: 'ready'
      }
    })
  );

  app.get(
    '/version',
    {
      schema: {
        tags: ['Platform'],
        summary: 'Application version'
      }
    },
    async (request) => ({
      success: true,
      requestId: request.id,
      data: {
        name: 'SportsOS API',
        version: '0.3.5',
        nodeVersion: process.version
      }
    })
  );
}
