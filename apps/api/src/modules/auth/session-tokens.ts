import { createHash, randomBytes } from "node:crypto";

export const REFRESH_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export function createRefreshToken(): string {
  return randomBytes(48).toString("base64url");
}

export function hashRefreshToken(refreshToken: string): string {
  return createHash("sha256").update(refreshToken, "utf8").digest("hex");
}
