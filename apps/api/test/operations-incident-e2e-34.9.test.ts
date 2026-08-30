import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import Fastify from "fastify";

import {
  listOperationsIncidents,
  readOperationsIncidentJournal,
} from "../src/services/operationsIncidentJournal.js";
import {
  persistSynthesizedOperationsIncidents,
} from "../src/services/operationsIncidentSynthesis.js";
import {
  OPERATIONS_INCIDENTS_PATH,
  registerOperationsIncidentRoutes,
} from "../src/routes/operationsIncidents.js";

const TOKEN = "sportsos-m34-9-fault-injection-token-0123456789";
let tempRoot = "";

beforeEach(async () => {
  tempRoot = await mkdtemp(path.join(os.tmpdir(), "sportsos-m34-9-"));
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

describe("Milestone 34.9 controlled incident lifecycle", () => {
  it("synthesizes one durable critical incident from injected recovery telemetry", async () => {
    await persistSynthesizedOperationsIncidents({
      recovery: {
        recentFailures: 1,
        services: [
          {
            service: "api",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          },
        ],
      },
    });

    const incidents = await listOperationsIncidents();
    expect(incidents.length).toBeGreaterThanOrEqual(1);

    const apiIncident = incidents.find(
      (incident) => incident.fingerprint === "recovery:api:budget-exhausted",
    );

    expect(apiIncident).toBeDefined();
    expect(apiIncident?.severity).toBe("critical");
    expect(apiIncident?.status).toBe("open");
    expect(apiIncident?.events.at(0)?.type).toBe("opened");
  });

  it("deduplicates repeated injected telemetry instead of opening duplicate incidents", async () => {
    const telemetry = {
      recovery: {
        services: [
          {
            service: "api",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          },
        ],
      },
    };

    await persistSynthesizedOperationsIncidents(telemetry);
    await persistSynthesizedOperationsIncidents(telemetry);

    const incidents = await listOperationsIncidents();
    const matching = incidents.filter(
      (incident) => incident.fingerprint === "recovery:api:budget-exhausted",
    );

    expect(matching).toHaveLength(1);
    expect(matching[0]?.occurrences).toBe(2);
    expect(matching[0]?.events.map((event) => event.type)).toEqual([
      "opened",
      "updated",
    ]);
  });

  it("supports authenticated acknowledge and resolve transitions end to end", async () => {
    await persistSynthesizedOperationsIncidents({
      recovery: {
        services: [
          {
            service: "api",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          },
        ],
      },
    });

    const incident = (await listOperationsIncidents()).find(
      (item) => item.fingerprint === "recovery:api:budget-exhausted",
    );
    expect(incident).toBeDefined();

    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    const ack = await app.inject({
      method: "POST",
      url: `${OPERATIONS_INCIDENTS_PATH}/${incident!.id}/acknowledge`,
      headers: { authorization: `Bearer ${TOKEN}` },
      payload: {
        actor: "m34.9-operator",
        note: "Investigating controlled fault.",
      },
    });

    expect(ack.statusCode).toBe(200);
    expect(ack.json().data.incident.status).toBe("acknowledged");

    const resolve = await app.inject({
      method: "POST",
      url: `${OPERATIONS_INCIDENTS_PATH}/${incident!.id}/resolve`,
      headers: { authorization: `Bearer ${TOKEN}` },
      payload: {
        actor: "m34.9-operator",
        note: "Controlled fault cleared.",
      },
    });

    expect(resolve.statusCode).toBe(200);
    expect(resolve.json().data.incident.status).toBe("resolved");

    const persisted = await readOperationsIncidentJournal();
    const finalIncident = persisted.incidents.find(
      (item) => item.id === incident!.id,
    );

    expect(finalIncident?.events.map((event) => event.type)).toEqual([
      "opened",
      "acknowledged",
      "resolved",
    ]);

    await app.close();
  });

  it("reopens the same incident if the signal recurs after resolution", async () => {
    const telemetry = {
      recovery: {
        services: [
          {
            service: "api",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          },
        ],
      },
    };

    await persistSynthesizedOperationsIncidents(telemetry);
    const incident = (await listOperationsIncidents()).find(
      (item) => item.fingerprint === "recovery:api:budget-exhausted",
    );
    expect(incident).toBeDefined();

    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    await app.inject({
      method: "POST",
      url: `${OPERATIONS_INCIDENTS_PATH}/${incident!.id}/resolve`,
      headers: { authorization: `Bearer ${TOKEN}` },
      payload: { actor: "m34.9-operator" },
    });

    await persistSynthesizedOperationsIncidents(telemetry);

    const reopened = (await listOperationsIncidents()).find(
      (item) => item.id === incident!.id,
    );

    expect(reopened?.status).toBe("open");
    expect(reopened?.occurrences).toBe(2);
    expect(reopened?.events.map((event) => event.type)).toEqual([
      "opened",
      "resolved",
      "reopened",
    ]);

    await app.close();
  });

  it("rejects unauthenticated lifecycle mutations", async () => {
    await persistSynthesizedOperationsIncidents({
      recovery: {
        services: [
          {
            service: "api",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          },
        ],
      },
    });

    const incident = (await listOperationsIncidents()).find(
      (item) => item.fingerprint === "recovery:api:budget-exhausted",
    );
    expect(incident).toBeDefined();

    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    const response = await app.inject({
      method: "POST",
      url: `${OPERATIONS_INCIDENTS_PATH}/${incident!.id}/resolve`,
      payload: { actor: "unauthorized" },
    });

    expect(response.statusCode).toBe(403);

    await app.close();
  });
});
