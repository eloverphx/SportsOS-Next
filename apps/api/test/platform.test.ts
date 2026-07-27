import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { API_NAME, API_VERSION } from "../src/platform/metadata.js";

describe("platform HTTP API", () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    const { buildApp } = await import("../src/app.js");

    app = await buildApp({
      logger: false,
      realtime: false,
    });

    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it("returns API metadata from GET /", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/",
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["x-request-id"]).toBeDefined();

    expect(response.json()).toMatchObject({
      success: true,
      data: {
        name: API_NAME,
        version: API_VERSION,
        environment: "test",
        documentation: "/docs",
      },
    });
  });

  it("returns readiness information", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/ready",
    });

    expect(response.statusCode).toBe(200);

    expect(response.json()).toMatchObject({
      success: true,
      data: {
        status: "ready",
      },
    });
  });

  it("returns version information", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/version",
    });

    expect(response.statusCode).toBe(200);

    const body = response.json();

    expect(body).toMatchObject({
      success: true,
      data: {
        name: API_NAME,
        version: API_VERSION,
      },
    });

    expect(body.data.nodeVersion).toBe(process.version);
  });

  it("serves the Swagger UI", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/docs/",
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("text/html");
    expect(response.body).toContain("Swagger UI");
  });

  it("returns the generated OpenAPI document", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/docs/json",
    });

    expect(response.statusCode).toBe(200);

    const document = response.json();

    expect(document.info).toMatchObject({
      title: API_NAME,
      version: API_VERSION,
    });

    expect(document.paths).toHaveProperty("/");
    expect(document.paths).toHaveProperty("/ready");
    expect(document.paths).toHaveProperty("/version");
  });

  it("uses the standardized not-found response", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/route-that-does-not-exist",
    });

    expect(response.statusCode).toBe(404);
    expect(response.headers["x-request-id"]).toBeDefined();

    expect(response.json()).toMatchObject({
      success: false,
      error: {
        code: "ROUTE_NOT_FOUND",
        message: "Route GET /route-that-does-not-exist was not found",
      },
    });
  });

  it("adds security and rate-limit headers", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/ready",
    });

    expect(response.headers["x-content-type-options"]).toBe("nosniff");
    expect(response.headers["x-ratelimit-limit"]).toBe("300");
    expect(response.headers["x-ratelimit-remaining"]).toBeDefined();
  });
});
