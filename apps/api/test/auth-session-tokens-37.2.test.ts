import { describe, expect, it } from "vitest";
import {
  createRefreshToken,
  hashRefreshToken,
  REFRESH_SESSION_TTL_MS,
} from "../src/modules/auth/session-tokens.js";

describe("Milestone 37.2 refresh-session token security", () => {
  it("creates high-entropy opaque refresh tokens", () => {
    const first = createRefreshToken();
    const second = createRefreshToken();

    expect(first).not.toBe(second);
    expect(first.length).toBeGreaterThanOrEqual(64);
    expect(second.length).toBeGreaterThanOrEqual(64);
  });

  it("stores a deterministic SHA-256 representation instead of the raw token", () => {
    const token = createRefreshToken();
    const hash = hashRefreshToken(token);

    expect(hash).toMatch(/^[a-f0-9]{64}$/);
    expect(hash).not.toBe(token);
    expect(hashRefreshToken(token)).toBe(hash);
  });

  it("uses a 30-day durable refresh-session lifetime", () => {
    expect(REFRESH_SESSION_TTL_MS).toBe(30 * 24 * 60 * 60 * 1000);
  });
});
