import Fastify from "fastify";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { registerOperationsIncidentRoutes } from "../src/routes/operationsIncidents.js";
import {
  readOperationsIncidentJournal,
  resolveOperationsIncident,
} from "../src/services/operationsIncidentJournal.js";

const ORIGINAL_ENABLED =
  process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED;
const ORIGINAL_TOKEN =
  process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN;
const ORIGINAL_DIR =
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;

const TOKEN = "m35-6-test-token-0123456789-abcdefghijklmnopqrstuvwxyz";

let tempDir: string | null = null;

afterEach(async () => {
  if (ORIGINAL_ENABLED === undefined) {
    delete process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED;
  } else {
    process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = ORIGINAL_ENABLED;
  }

  if (ORIGINAL_TOKEN === undefined) {
    delete process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN;
  } else {
    process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN = ORIGINAL_TOKEN;
  }

  if (ORIGINAL_DIR === undefined) {
    delete process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;
  } else {
    process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = ORIGINAL_DIR;
  }

  if (tempDir) {
    await fs.rm(tempDir, { recursive: true, force: true });
    tempDir = null;
  }
});

async function createApp() {
  tempDir = await fs.mkdtemp(
    path.join(os.tmpdir(), "sportsos-m35-6-"),
  );

  process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = "true";
  process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN = TOKEN;
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = tempDir;

  const app = Fastify();
  await registerOperationsIncidentRoutes(app);
  return app;
}

describe("Milestone 35.6 delivery failure incident integration", () => {
  it("protects the delivery failure signal route", async () => {
    const app = await createApp();

    const response = await app.inject({
      method: "POST",
      url:
        "/deployment/operations/incidents/signals/escalation-delivery-failure",
      payload: {
        incidentId: "inc-original",
        channel: "webhook",
      },
    });

    expect(response.statusCode).toBe(403);
    await app.close();
  });

  it("dedupes repeated failures into one deterministic incident", async () => {
    const app = await createApp();

    const signal = async (incidentId: string) =>
      app.inject({
        method: "POST",
        url:
          "/deployment/operations/incidents/signals/escalation-delivery-failure",
        headers: {
          authorization: `Bearer ${TOKEN}`,
        },
        payload: {
          incidentId,
          channel: "webhook",
          detail: "synthetic delivery failure",
          observedAt: new Date().toISOString(),
        },
      });

    const first = await signal("inc-a");
    const second = await signal("inc-b");

    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);

    const journal = await readOperationsIncidentJournal();
    expect(journal.incidents).toHaveLength(1);

    const incident = journal.incidents[0];
    expect(incident?.fingerprint).toBe(
      "operations:incident-escalation-delivery-failure",
    );
    expect(incident?.source).toBe("operations");
    expect(incident?.severity).toBe("critical");
    expect(incident?.occurrences).toBe(2);

    await app.close();
  });

  it("reopens the same incident after resolution instead of creating a recursion chain", async () => {
    const app = await createApp();

    const first = await app.inject({
      method: "POST",
      url:
        "/deployment/operations/incidents/signals/escalation-delivery-failure",
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
      payload: {
        incidentId: "inc-original",
        channel: "webhook",
        detail: "first failure",
      },
    });

    const firstBody = first.json();
    const incidentId = firstBody.data.incident.id as string;

    await resolveOperationsIncident(incidentId, {
      actor: "m35.6-test",
      note: "synthetic resolution",
    });

    const second = await app.inject({
      method: "POST",
      url:
        "/deployment/operations/incidents/signals/escalation-delivery-failure",
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
      payload: {
        incidentId,
        channel: "webhook",
        detail: "failure after resolution",
      },
    });

    expect(second.statusCode).toBe(200);

    const journal = await readOperationsIncidentJournal();
    expect(journal.incidents).toHaveLength(1);

    const incident = journal.incidents[0];
    expect(incident?.id).toBe(incidentId);
    expect(incident?.status).toBe("open");
    expect(incident?.occurrences).toBe(2);
    expect(
      incident?.events.some((event) => event.type === "reopened"),
    ).toBe(true);

    await app.close();
  });

  it("signals only inside the actual webhook failure branch and has no recovery authority", async () => {
    // SPORTSOS_M35_6_3_STABLE_REPO_ROOT
    // Vitest may execute this workspace with process.cwd() === apps/api.
    // Resolve the repository root from this test file instead.
    const repoRoot = path.resolve(
      path.dirname(new URL(import.meta.url).pathname),
      "../../..",
    );

    const escalation = await fs.readFile(
      path.join(
        repoRoot,
        "scripts/operations-incident-escalation.sh",
      ),
      "utf8",
    );

    expect(escalation).toContain(
      "SPORTSOS_M35_6_DELIVERY_FAILURE_SIGNAL",
    );
    expect(escalation).toContain(
      "signals/escalation-delivery-failure",
    );
    expect(escalation).toContain(
      "signalDeliveryFailure(incident, deliveryDetail);",
    );

    expect(escalation).not.toMatch(
      /\bdocker\s+(restart|stop|kill|rm)\b/,
    );
    expect(escalation).not.toMatch(
      /\bdocker\s+compose\s+(restart|stop|down|rm)\b/,
    );
  });
});
