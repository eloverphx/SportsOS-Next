import Fastify from "fastify";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { afterEach, describe, expect, it } from "vitest";

import { registerOperationsIncidentRoutes } from "../src/routes/operationsIncidents.js";
import {
  openOrUpdateOperationsIncident,
  readOperationsIncidentJournal,
  resolveOperationsIncident,
} from "../src/services/operationsIncidentJournal.js";

const ORIGINAL_ENABLED =
  process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED;
const ORIGINAL_TOKEN =
  process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN;
const ORIGINAL_DIR =
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;

const TOKEN =
  "m35-7-test-token-0123456789-abcdefghijklmnopqrstuvwxyz";

let tempDir: string | null = null;

afterEach(async () => {
  if (ORIGINAL_ENABLED === undefined) {
    delete process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED;
  } else {
    process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED =
      ORIGINAL_ENABLED;
  }

  if (ORIGINAL_TOKEN === undefined) {
    delete process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN;
  } else {
    process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN =
      ORIGINAL_TOKEN;
  }

  if (ORIGINAL_DIR === undefined) {
    delete process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;
  } else {
    process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR =
      ORIGINAL_DIR;
  }

  if (tempDir) {
    await fs.rm(tempDir, { recursive: true, force: true });
    tempDir = null;
  }
});

describe("Milestone 35.7 controlled notification fault injection", () => {
  it("dedupes repeated delivery failures into one durable incident", async () => {
    tempDir = await fs.mkdtemp(
      path.join(os.tmpdir(), "sportsos-m35-7-"),
    );

    process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = "true";
    process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN = TOKEN;
    process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = tempDir;

    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    const signal = async (failedIncidentId: string) =>
      app.inject({
        method: "POST",
        url:
          "/deployment/operations/incidents/signals/escalation-delivery-failure",
        headers: {
          authorization: `Bearer ${TOKEN}`,
        },
        payload: {
          incidentId: failedIncidentId,
          channel: "webhook",
          detail: "synthetic unreachable webhook",
          observedAt: new Date().toISOString(),
        },
      });

    const first = await signal("inc-source-a");
    const second = await signal("inc-source-b");

    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);

    const journal = await readOperationsIncidentJournal();
    expect(journal.incidents).toHaveLength(1);

    const failureIncident = journal.incidents[0];

    expect(failureIncident?.fingerprint).toBe(
      "operations:incident-escalation-delivery-failure",
    );
    expect(failureIncident?.severity).toBe("critical");
    expect(failureIncident?.source).toBe("operations");
    expect(failureIncident?.occurrences).toBe(2);

    await app.close();
  });

  it("reopens the same delivery failure incident after resolution", async () => {
    tempDir = await fs.mkdtemp(
      path.join(os.tmpdir(), "sportsos-m35-7-reopen-"),
    );

    process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED = "true";
    process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN = TOKEN;
    process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = tempDir;

    const app = Fastify();
    await registerOperationsIncidentRoutes(app);

    const first = await app.inject({
      method: "POST",
      url:
        "/deployment/operations/incidents/signals/escalation-delivery-failure",
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
      payload: {
        incidentId: "inc-source",
        channel: "webhook",
        detail: "first synthetic failure",
      },
    });

    const incidentId = first.json().data.incident.id as string;

    await resolveOperationsIncident(incidentId, {
      actor: "m35.7-test",
      note: "synthetic resolution before repeat failure",
    });

    const second = await app.inject({
      method: "POST",
      url:
        "/deployment/operations/incidents/signals/escalation-delivery-failure",
      headers: {
        authorization: `Bearer ${TOKEN}`,
      },
      payload: {
        incidentId: "inc-source-repeat",
        channel: "webhook",
        detail: "second synthetic failure",
      },
    });

    expect(second.statusCode).toBe(200);

    const journal = await readOperationsIncidentJournal();
    expect(journal.incidents).toHaveLength(1);

    const failureIncident = journal.incidents[0];
    expect(failureIncident?.id).toBe(incidentId);
    expect(failureIncident?.status).toBe("open");
    expect(failureIncident?.occurrences).toBe(2);
    expect(
      failureIncident?.events.some(
        (event) => event.type === "reopened",
      ),
    ).toBe(true);

    await app.close();
  });

  it("escalation shell keeps notification-only authority", async () => {
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

    expect(escalation).not.toMatch(
      /\bdocker\s+(restart|stop|kill|rm)\b/,
    );
    expect(escalation).not.toMatch(
      /\bdocker\s+compose\s+(restart|stop|down|rm)\b/,
    );
    expect(escalation).not.toMatch(/\bsystemctl\s+(restart|stop)\b/);
  });

  it("status telemetry recognizes failed webhook delivery rows", async () => {
    const repoRoot = path.resolve(
      path.dirname(new URL(import.meta.url).pathname),
      "../../..",
    );

    const statusScript = await fs.readFile(
      path.join(
        repoRoot,
        "scripts/operations-incident-escalation-status.sh",
      ),
      "utf8",
    );

    // SPORTSOS_M35_7_1_TELEMETRY_CONTRACT_ASSERTION
    expect(statusScript).toContain(
      "recentDeliveryFailureCount",
    );
    expect(statusScript).toContain(
      'haystack.includes("fail")',
    );
    expect(statusScript).toContain(
      'haystack.includes("error")',
    );
    expect(statusScript).toContain(
      'haystack.includes("timeout")',
    );
    expect(statusScript).toContain(
      "row.action",
    );
    expect(statusScript).toContain(
      "row.result",
    );
    expect(statusScript).toContain(
      "row.detail",
    );
  });
});
