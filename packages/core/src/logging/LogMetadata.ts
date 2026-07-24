export type LogPrimitive = string | number | boolean | null;

export type LogValue =
  | LogPrimitive
  | ReadonlyArray<LogPrimitive>
  | Record<string, unknown>;

export interface LogMetadata {
  requestId?: string;
  correlationId?: string;
  userId?: string;
  organizationId?: string;
  module?: string;
  action?: string;
  durationMs?: number;
  error?: unknown;
  [key: string]: LogValue | unknown;
}