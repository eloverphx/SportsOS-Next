import { randomBytes } from "node:crypto";

export interface CameraIngestSessionConfig {
  readonly gameId: string;
  readonly protocol: "srt";
  readonly host: string;
  readonly port: number;
  readonly latencyMs: number;
  readonly mode: "caller";
  readonly streamId: string;
  readonly issuedAt: string;
  readonly expiresAt: string;
}

export interface CameraIngestEnvironment {
  readonly SPORTSOS_CAMERA_INGEST_HOST?: string;
  readonly SPORTSOS_CAMERA_INGEST_PORT?: string;
  readonly SPORTSOS_CAMERA_INGEST_LATENCY_MS?: string;
  readonly SPORTSOS_CAMERA_INGEST_SESSION_TTL_SECONDS?: string;
}

function positiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);

  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

export function resolveCameraIngestEndpoint(environment: CameraIngestEnvironment): {
  host: string;
  port: number;
  latencyMs: number;
  sessionTtlSeconds: number;
} {
  const host = environment.SPORTSOS_CAMERA_INGEST_HOST?.trim();

  if (!host) {
    throw new Error("SPORTSOS_CAMERA_INGEST_HOST is not configured");
  }

  const port = positiveInteger(environment.SPORTSOS_CAMERA_INGEST_PORT, 9000);

  if (port > 65_535) {
    throw new Error("SPORTSOS_CAMERA_INGEST_PORT is invalid");
  }

  return {
    host,
    port,
    latencyMs: positiveInteger(environment.SPORTSOS_CAMERA_INGEST_LATENCY_MS, 120),
    sessionTtlSeconds: positiveInteger(environment.SPORTSOS_CAMERA_INGEST_SESSION_TTL_SECONDS, 900),
  };
}

export function issueCameraIngestSession(input: {
  gameId: string;
  now?: Date;
  environment?: CameraIngestEnvironment;
  randomBytes?: (size: number) => Buffer;
}): CameraIngestSessionConfig {
  const gameId = input.gameId.trim();

  if (!gameId) {
    throw new Error("Game ID is required");
  }

  const endpoint = resolveCameraIngestEndpoint(input.environment ?? process.env);

  const issuedAt = input.now ?? new Date();

  const expiresAt = new Date(issuedAt.getTime() + endpoint.sessionTtlSeconds * 1000);

  const random = input.randomBytes ?? randomBytes;

  /*
   * The streamId is deliberately opaque.
   *
   * It is not a permanent credential and is never derived
   * from the game's ID or any destination stream key.
   */
  const token = random(24).toString("base64url");

  return {
    gameId,
    protocol: "srt",
    host: endpoint.host,
    port: endpoint.port,
    latencyMs: endpoint.latencyMs,
    mode: "caller",
    streamId: `sportsos:${gameId}:${token}`,
    issuedAt: issuedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
  };
}
