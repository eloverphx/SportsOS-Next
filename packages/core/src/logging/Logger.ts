import type { LogMetadata } from "./LogMetadata.js";

export interface Logger {
  debug(message: string, metadata?: LogMetadata): void;
  info(message: string, metadata?: LogMetadata): void;
  warn(message: string, metadata?: LogMetadata): void;
  error(message: string, metadata?: LogMetadata): void;

  child(metadata: LogMetadata): Logger;
}