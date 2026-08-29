import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  findOperationsIncidentById,
  listOperationsIncidents,
  openOrUpdateOperationsIncident,
  readOperationsIncidentJournal,
} from "../src/services/operationsIncidentJournal.js";

const tempRoots: string[] = [];

async function withTempJournal(): Promise<string> {
  const root = await mkdtemp(
    path.join(os.tmpdir(), "sportsos-incidents-"),
  );
  tempRoots.push(root);
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = root;
  return root;
}

afterEach(async () => {
  delete process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;
  await Promise.all(
    tempRoots.splice(0).map((root) =>
      rm(root, { recursive: true, force: true }),
    ),
  );
});

describe("Milestone 34.2 operations incident journal", () => {
  it("returns an empty schema-v1 journal when no runtime file exists", async () => {
    await withTempJournal();

    const journal = await readOperationsIncidentJournal();

    expect(journal.schemaVersion).toBe(1);
    expect(journal.incidents).toEqual([]);
  });

  it("creates a durable incident with an opened audit event", async () => {
    const root = await withTempJournal();

    const incident = await openOrUpdateOperationsIncident({
      fingerprint: "recovery:api:restart-failed",
      source: "recovery",
      severity: "critical",
      title: "API recovery failed",
      summary: "The API remained unhealthy after bounded recovery.",
      service: "api",
      metadata: {
        reason: "post-verification",
      },
      observedAt: "2026-08-28T20:00:00.000Z",
    });

    expect(incident.status).toBe("open");
    expect(incident.occurrences).toBe(1);
    expect(incident.events).toHaveLength(1);
    expect(incident.events[0]?.type).toBe("opened");

    const raw = await readFile(
      path.join(root, "incidents.json"),
      "utf8",
    );
    expect(raw).toContain("recovery:api:restart-failed");

    const stored = await findOperationsIncidentById(incident.id);
    expect(stored?.service).toBe("api");
  });

  it("deduplicates by normalized fingerprint and increments occurrences", async () => {
    await withTempJournal();

    const first = await openOrUpdateOperationsIncident({
      fingerprint: " Reliability: Failure-Streak ",
      source: "reliability",
      severity: "warning",
      title: "Reliability degraded",
      summary: "Failure streak detected.",
      observedAt: "2026-08-28T20:01:00.000Z",
    });

    const second = await openOrUpdateOperationsIncident({
      fingerprint: "reliability: failure-streak",
      source: "reliability",
      severity: "critical",
      title: "Reliability critical",
      summary: "Failure streak crossed critical threshold.",
      observedAt: "2026-08-28T20:02:00.000Z",
    });

    expect(second.id).toBe(first.id);
    expect(second.occurrences).toBe(2);
    expect(second.severity).toBe("critical");
    expect(second.events.at(-1)?.type).toBe("updated");

    const incidents = await listOperationsIncidents();
    expect(incidents).toHaveLength(1);
  });

  it("keeps incident runtime data outside tracked source paths", async () => {
    const root = await withTempJournal();

    await openOrUpdateOperationsIncident({
      fingerprint: "health:mysql:offline",
      source: "health",
      severity: "critical",
      title: "MySQL offline",
      summary: "Database health probe failed.",
      service: "mysql",
    });

    expect(root).not.toContain("/apps/");
    expect(root).not.toContain("/scripts/");
  });
});
