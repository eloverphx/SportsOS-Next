import {
  sportsOSEnvironmentSchema,
  type SportsOSEnvironment
} from './schema.js';
import { formatConfigurationError } from './errors.js';

export interface SportsOSConfig {
  readonly environment: {
    readonly name: SportsOSEnvironment['NODE_ENV'];
    readonly isDevelopment: boolean;
    readonly isTest: boolean;
    readonly isProduction: boolean;
  };

  readonly api: {
    readonly host: string;
    readonly port: number;
    readonly publicUrl: string;
  };

  readonly dashboard: {
    readonly origin: string;
  };

  readonly database: {
    readonly host: string;
    readonly port: number;
    readonly name: string;
    readonly user: string;
    readonly password: string;
  };

  readonly auth: {
    readonly jwtSecret: string;
  };

  readonly redis: {
    readonly url: string;
  };

  readonly mqtt: {
    readonly url: string;
  };

  readonly storage: {
    readonly endpoint: string;
    readonly port: number;
    readonly accessKey: string;
    readonly secretKey: string;
    readonly bucket: string;
    readonly useSsl: boolean;
  };
}

export function createConfig(
  source: NodeJS.ProcessEnv = process.env
): SportsOSConfig {
  const result = sportsOSEnvironmentSchema.safeParse(source);

  if (!result.success) {
    throw formatConfigurationError(result.error);
  }

  const env = result.data;

  return Object.freeze({
    environment: Object.freeze({
      name: env.NODE_ENV,
      isDevelopment: env.NODE_ENV === 'development',
      isTest: env.NODE_ENV === 'test',
      isProduction: env.NODE_ENV === 'production'
    }),

    api: Object.freeze({
      host: env.HOST,
      port: env.PORT,
      publicUrl: env.PUBLIC_API_URL
    }),

    dashboard: Object.freeze({
      origin: env.DASHBOARD_ORIGIN
    }),

    database: Object.freeze({
      host: env.MYSQL_HOST,
      port: env.MYSQL_PORT,
      name: env.MYSQL_DATABASE,
      user: env.MYSQL_USER,
      password: env.MYSQL_PASSWORD
    }),

    auth: Object.freeze({
      jwtSecret: env.JWT_SECRET
    }),

    redis: Object.freeze({
      url: env.REDIS_URL
    }),

    mqtt: Object.freeze({
      url: env.MQTT_URL
    }),

    storage: Object.freeze({
      endpoint: env.MINIO_ENDPOINT,
      port: env.MINIO_PORT,
      accessKey: env.MINIO_ACCESS_KEY,
      secretKey: env.MINIO_SECRET_KEY,
      bucket: env.MINIO_BUCKET,
      useSsl: false
    })
  });
}
