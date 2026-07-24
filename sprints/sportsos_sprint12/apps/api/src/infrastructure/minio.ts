import { Client as MinioClient } from 'minio';
import { env } from '../config/env.js';

export const minio = new MinioClient({
  endPoint: env.MINIO_ENDPOINT,
  port: env.MINIO_PORT,
  useSSL: false,
  accessKey: env.MINIO_ACCESS_KEY,
  secretKey: env.MINIO_SECRET_KEY
});
