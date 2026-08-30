import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import Fastify from "fastify";

import {
  openOrUpdateOperationsIncident,
} from "../src/services/operationsIncidentJournal.js";
import {
  OPERATIONS_INCIDENTS_PATH,
  registerOperationsIncidentRoutes,
} from "../src/routes/operationsIncidents.js";

const TOKEN =
  "sportsos-operations-incident-test-token-0123456789";

let tempRoot = "";

beforeEach(async () => {
  tempRoot = await mkdtemp(
    path.join(os.tmpdir(), "sportsos-incidents-api-"),
  );
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = tempRoot;
  process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = "true";
  process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN = TOKEN;
});

afterEach(async () => {
  delete process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;
  delete process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED;
  delete process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN;

  if (tempRoot) {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

async function buildApp() {
  const app = Fastify();
  await registerOperationsIncidentRoutes(app);
  return app;
}

describe("Milestone 34.4 protected operations incident API", () => {
  it("returns 403 without the bearer token", async () => {
    const app = await buildApp();

    const response = await app.inject({
      method: "GET",
      url: OPERATIONS_INCIDENTS_PATH,
    });

    expect(response.statusCode).toBe(403);
    expect(response.headers["cache-control"]).toBe("no-store");

    await app.close();
  });

  it("returns 404 when protected operations access is disabled", async () => {
    process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = "false";
    const app = await buildApp();

    const response = await app.inject({
      method: "GET",
      url: OPERATIONS_INCIDENTS_PATH,
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
    });

    expect(response.statusCode).toBe(404);

    await app.close();
  });

  it("returns incident summaries and incidents to an authorized caller", async () => {
    await openOrUpdateOperationsIncident({
      fingerprint: "recovery:api:budget-exhausted",
      source: "recovery",
      severity: "critical",
      title: "Recovery budget exhausted for api",
      summary: "Automatic recovery budget exhausted.",
      service: "api",
      observedAt: "2026-08-28T21:10:00.000Z",
    });

    const app = await buildApp();

    const response = await app.inject({
      method: "GET",
      url: OPERATIONS_INCIDENTS_PATH,
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["cache-control"]).toBe("no-store");

    const body = response.json();
    expect(body.success).toBe(true);
    expect(body.data.schemaVersion).toBe(1);
    expect(body.data.summary.total).toBe(1);
    expect(body.data.summary.open).toBe(1);
    expect(body.data.summary.critical).toBe(1);
    expect(body.data.incidents).toHaveLength(1);

    await app.close();
  });

  it("returns a single incident by id and 404 for an unknown id", async () => {
    const incident = await openOrUpdateOperationsIncident({
      fingerprint: "reliability:warning:test",
      source: "reliability",
      severity: "warning",
      title: "Reliability warning",
      summary: "Synthetic test incident.",
      observedAt: "2026-08-28T21:11:00.000Z",
    });

    const app = await buildApp();

    const found = await app.inject({
      method: "GET",
      url: `${OPERATIONS_INCIDENTS_PATH}/${incident.id}`,
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
    });

    expect(found.statusCode).toBe(200);
    expect(found.json().data.incident.id).toBe(incident.id);

    const missing = await app.inject({
      method: "GET",
      url: `${OPERATIONS_INCIDENTS_PATH}/inc_missing`,
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
    });

    expect(missing.statusCode).toBe(404);
    expect(missing.json().error.code)
      .toBe("OPERATIONS_INCIDENT_NOT_FOUND");

    await app.close();
  });

  it("does not provide mutation routes", async () => {
    const app = await buildApp();

    for (const method of ["POST", "PUT", "PATCH", "DELETE"] as const) {
      const response = await app.inject({
        method,
        url: OPERATIONS_INCIDENTS_PATH,
        headers: {
          authorization: `Bearer ${TOKEN}`,
        },
      });

      expect(response.statusCode).toBe(404);
    }

    await app.close();
  });
});
