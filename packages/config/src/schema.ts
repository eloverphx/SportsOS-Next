import { z } from 'zod';

export const sportsOSEnvironmentSchema = z.object({
  NODE_ENV: z
    .enum(['development', 'test', 'production'])
    .default('development'),

  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65535).default(4001),

  DASHBOARD_ORIGIN: z.string().default('http://localhost:4000'),
  PUBLIC_API_URL: z.string().default('http://localhost:4001'),

  MYSQL_HOST: z.string().default('mysql'),
  MYSQL_PORT: z.coerce.number().int().min(1).max(65535).default(3306),
  MYSQL_DATABASE: z.string().default('sportsos'),
  MYSQL_USER: z.string().default('sportsos'),
  MYSQL_PASSWORD: z.string().min(1),

  JWT_SECRET: z.string().min(32),

  REDIS_URL: z.string().default('redis://redis:6379'),
  MQTT_URL: z.string().default('mqtt://mqtt:1883'),

  MINIO_ENDPOINT: z.string().default('minio'),
  MINIO_PORT: z.coerce.number().int().min(1).max(65535).default(9000),
  MINIO_ACCESS_KEY: z.string().min(1),
  MINIO_SECRET_KEY: z.string().min(1),
  MINIO_BUCKET: z.string().default('sportsos-media')
});

export type SportsOSEnvironment = z.infer<
  typeof sportsOSEnvironmentSchema
>;
