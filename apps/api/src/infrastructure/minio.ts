import { Client as MinioClient } from "minio";
import { config } from "@sportsos/config";

export const minio = new MinioClient({
  endPoint: config.storage.endpoint,
  port: config.storage.port,
  useSSL: config.storage.useSsl,
  accessKey: config.storage.accessKey,
  secretKey: config.storage.secretKey,
});
