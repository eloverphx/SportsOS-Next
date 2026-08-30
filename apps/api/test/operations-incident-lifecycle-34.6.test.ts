import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import Fastify from "fastify";

import {
  acknowledgeOperationsIncident,
  openOrUpdateOperationsIncident,
  resolveOperationsIncident,
} from "../src/services/operationsIncidentJournal.js";
import {
  OPERATIONS_INCIDENTS_PATH,
  registerOperationsIncidentRoutes,
} from "../src/routes/operationsIncidents.js";

const TOKEN = "sportsos-m34-6-protected-lifecycle-token-0123456789";
let tempRoot = "";

beforeEach(async () => {
  tempRoot = await mkdtemp(path.join(os.tmpdir(), "sportsos-m34-6-"));
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = tempRoot;
  process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = "true";
  process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN = TOKEN;
});

afterEach(async () => {
  delete process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;
  delete process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED;
  delete process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN;
  if (tempRoot) await rm(tempRoot, { recursive: true, force: true });
});

async function seed() {
  return openOrUpdateOperationsIncident({
    fingerprint: "recovery:api:test-lifecycle",
    source: "recovery",
    severity: "critical",
    title: "Lifecycle test",
    summary: "Lifecycle test incident.",
    service: "api",
    observedAt: "2026-08-28T21:20:00.000Z",
  });
}

describe("Milestone 34.6 incident lifecycle", () => {
  it("acknowledges and resolves durably with audit events", async () => {
    const opened = await seed();
    const acknowledged = await acknowledgeOperationsIncident(opened.id, {
      actor: "operator@example.test",
      note: "Investigating.",
      observedAt: "2026-08-28T21:21:00.000Z",
    });
    expect(acknowledged?.status).toBe("acknowledged");
    expect(acknowledged?.acknowledgedBy).toBe("operator@example.test");
    expect(acknowledged?.events.at(-1)?.type).toBe("acknowledged");

    const resolved = await resolveOperationsIncident(opened.id, {
      actor: "operator@example.test",
      note: "Service stable.",
      observedAt: "2026-08-28T21:22:00.000Z",
    });
    expect(resolved?.status).toBe("resolved");
    expect(resolved?.resolvedBy).toBe("operator@example.test");
    expect(resolved?.events.map((event) => event.type))
      .toEqual(["opened", "acknowledged", "resolved"]);
  });

  it("requires authorization for lifecycle routes", async () => {
    const opened = await seed();
    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    const response = await app.inject({
      method: "POST",
      url: `${OPERATIONS_INCIDENTS_PATH}/${opened.id}/acknowledge`,
      payload: { actor: "operator@example.test" },
    });
    expect(response.statusCode).toBe(403);
    await app.close();
  });

  it("requires an explicit operator actor", async () => {
    const opened = await seed();
    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    const response = await app.inject({
      method: "POST",
      url: `${OPERATIONS_INCIDENTS_PATH}/${opened.id}/acknowledge`,
      headers: { authorization: `Bearer ${TOKEN}` },
      payload: {},
    });
    expect(response.statusCode).toBe(400);
    expect(response.json().error.code).toBe("INVALID_INCIDENT_ACTOR");
    await app.close();
  });

  it("does not allow acknowledgement after resolution", async () => {
    const opened = await seed();
    await resolveOperationsIncident(opened.id, {
      actor: "operator@example.test",
      observedAt: "2026-08-28T21:22:00.000Z",
    });

    await expect(
      acknowledgeOperationsIncident(opened.id, {
        actor: "operator@example.test",
      }),
    ).rejects.toThrow("Resolved operations incidents cannot be acknowledged.");
  });

  it("is idempotent for repeated acknowledgement and resolution", async () => {
    const opened = await seed();
    const firstAck = await acknowledgeOperationsIncident(opened.id, {
      actor: "operator@example.test",
    });
    const secondAck = await acknowledgeOperationsIncident(opened.id, {
      actor: "another@example.test",
    });
    expect(secondAck?.events.length).toBe(firstAck?.events.length);
    expect(secondAck?.acknowledgedBy).toBe("operator@example.test");

    const firstResolve = await resolveOperationsIncident(opened.id, {
      actor: "operator@example.test",
    });
    const secondResolve = await resolveOperationsIncident(opened.id, {
      actor: "another@example.test",
    });
    expect(secondResolve?.events.length).toBe(firstResolve?.events.length);
    expect(secondResolve?.resolvedBy).toBe("operator@example.test");
  });

  it("keeps synthesis separate from operator lifecycle authority", async () => {
    const synthesis = await import(
      "../src/services/operationsIncidentSynthesis.js"
    );
    expect(
      synthesis.synthesizeOperationsIncidentCandidates({
        recovery: {
          services: [{
            service: "api",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          }],
        },
      })[0]?.fingerprint,
    ).toBe("recovery:api:budget-exhausted");
    expect("acknowledgeOperationsIncident" in synthesis).toBe(false);
    expect("resolveOperationsIncident" in synthesis).toBe(false);
  });
});
