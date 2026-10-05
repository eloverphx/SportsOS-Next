import { describe, expect, it } from "vitest";
import {
  issueCameraIngestSession,
  resolveCameraIngestEndpoint,
} from "../src/services/cameraIngestSession.js";

describe("M41 camera ingest session", () => {
  it("resolves a configured SRT ingest endpoint", () => {
    expect(
      resolveCameraIngestEndpoint({
        SPORTSOS_CAMERA_INGEST_HOST: "192.168.5.3",
        SPORTSOS_CAMERA_INGEST_PORT: "9000",
        SPORTSOS_CAMERA_INGEST_LATENCY_MS: "120",
        SPORTSOS_CAMERA_INGEST_SESSION_TTL_SECONDS: "900",
      }),
    ).toEqual({
      host: "192.168.5.3",
      port: 9000,
      latencyMs: 120,
      sessionTtlSeconds: 900,
    });
  });

  it("issues a short-lived game-specific caller configuration", () => {
    const session = issueCameraIngestSession({
      gameId: "42",
      now: new Date("2026-10-05T15:00:00.000Z"),
      environment: {
        SPORTSOS_CAMERA_INGEST_HOST: "192.168.5.3",
        SPORTSOS_CAMERA_INGEST_PORT: "9000",
        SPORTSOS_CAMERA_INGEST_LATENCY_MS: "120",
        SPORTSOS_CAMERA_INGEST_SESSION_TTL_SECONDS: "900",
      },
      randomBytes: () => Buffer.alloc(24, 7),
    });

    expect(session.gameId).toBe("42");
    expect(session.protocol).toBe("srt");
    expect(session.mode).toBe("caller");
    expect(session.host).toBe("192.168.5.3");
    expect(session.port).toBe(9000);
    expect(session.latencyMs).toBe(120);
    expect(session.issuedAt).toBe("2026-10-05T15:00:00.000Z");
    expect(session.expiresAt).toBe("2026-10-05T15:15:00.000Z");
    expect(session.streamId).toMatch(/^sportsos:42:/);
  });

  it("generates a fresh stream ID for each session", () => {
    let counter = 1;

    const make = () =>
      issueCameraIngestSession({
        gameId: "42",
        environment: {
          SPORTSOS_CAMERA_INGEST_HOST: "192.168.5.3",
        },
        randomBytes: (size) => Buffer.alloc(size, counter++),
      });

    expect(make().streamId).not.toBe(make().streamId);
  });

  it("requires an ingest host", () => {
    expect(() => resolveCameraIngestEndpoint({})).toThrow(
      "SPORTSOS_CAMERA_INGEST_HOST is not configured",
    );
  });

  it("rejects an invalid configured port", () => {
    expect(() =>
      resolveCameraIngestEndpoint({
        SPORTSOS_CAMERA_INGEST_HOST: "192.168.5.3",
        SPORTSOS_CAMERA_INGEST_PORT: "70000",
      }),
    ).toThrow("SPORTSOS_CAMERA_INGEST_PORT is invalid");
  });
});
