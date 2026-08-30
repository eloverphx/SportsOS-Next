import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  persistSynthesizedOperationsIncidents,
  synthesizeOperationsIncidentCandidates,
} from "../src/services/operationsIncidentSynthesis.js";
import {
  listOperationsIncidents,
} from "../src/services/operationsIncidentJournal.js";

const tempRoots: string[] = [];

async function withTempJournal(): Promise<void> {
  const root = await mkdtemp(
    path.join(os.tmpdir(), "sportsos-incident-synth-"),
  );
  tempRoots.push(root);
  process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR = root;
}

afterEach(async () => {
  delete process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR;
  await Promise.all(
    tempRoots.splice(0).map((root) =>
      rm(root, { recursive: true, force: true }),
    ),
  );
});

describe("Milestone 34.3 incident synthesis", () => {
  it("creates deterministic candidates from reliability and recovery telemetry", () => {
    const candidates =
      synthesizeOperationsIncidentCandidates({
        overallStatus: "critical",
        severity: {
          status: "critical",
          reasons: [
            {
              severity: "critical",
              reason: "Failure streak 4 meets critical threshold 3.",
            },
          ],
        },
        recovery: {
          summary: {
            recentFailedRecoveries: 1,
          },
          services: [
            {
              service: "api",
              policy: "auto",
              guardrailState: "budget-exhausted",
              remainingBudget: 0,
            },
            {
              service: "dashboard",
              policy: "auto",
              guardrailState: "cooldown",
              cooldownRemainingSeconds: 450,
              remainingBudget: 1,
            },
          ],
        },
      });

    expect(candidates.map((candidate) => candidate.fingerprint))
      .toEqual([
        "recovery:api:budget-exhausted",
        "recovery:dashboard:cooldown",
        "recovery:recent-failure",
        "reliability:critical:failure-streak-4-meets-critical-threshold-3",
      ]);
  });

  it("does not synthesize incidents for a healthy recovery state", () => {
    const candidates =
      synthesizeOperationsIncidentCandidates({
        overallStatus: "healthy",
        severity: {
          status: "healthy",
          reasons: [],
        },
        recent: {
          totalRuns: 20,
          failedRuns: 0,
          passedRuns: 20,
        },
        recovery: {
          summary: {
            recentFailedRecoveries: 0,
            recentBlockedRecoveries: 0,
          },
          services: [
            {
              service: "api",
              policy: "auto",
              guardrailState: "ready",
              eligible: true,
              remainingBudget: 2,
              cooldownRemainingSeconds: 0,
            },
            {
              service: "mysql",
              policy: "monitor",
              guardrailState: "monitor-only",
              eligible: false,
            },
          ],
        },
      });

    expect(candidates).toEqual([]);
  });

  it("falls back to a warning incident when operations runs failed without stronger signals", () => {
    const candidates =
      synthesizeOperationsIncidentCandidates({
        recent: {
          totalRuns: 10,
          failedRuns: 2,
          passedRuns: 8,
        },
      });

    expect(candidates).toHaveLength(1);
    expect(candidates[0]?.fingerprint)
      .toBe("operations:recent-run-failure");
    expect(candidates[0]?.severity).toBe("warning");
  });

  it("persists repeated synthesized signals into one deduplicated incident", async () => {
    await withTempJournal();

    const status = {
      recovery: {
        services: [
          {
            service: "api",
            policy: "auto",
            guardrailState: "budget-exhausted",
            remainingBudget: 0,
          },
        ],
      },
    } as const;

    const first = await persistSynthesizedOperationsIncidents(
      status,
      "2026-08-28T21:00:00.000Z",
    );
    const second = await persistSynthesizedOperationsIncidents(
      status,
      "2026-08-28T21:01:00.000Z",
    );

    expect(first).toHaveLength(1);
    expect(second).toEqual(first);

    const incidents = await listOperationsIncidents();
    expect(incidents).toHaveLength(1);
    expect(incidents[0]?.occurrences).toBe(2);
    expect(incidents[0]?.events.map((event) => event.type))
      .toEqual(["opened", "updated"]);
  });

  it("deduplicates duplicate severity reasons in a single synthesis pass", () => {
    const candidates =
      synthesizeOperationsIncidentCandidates({
        severity: {
          status: "warning",
          reasons: [
            {
              severity: "warning",
              reason: "Failure rate exceeds threshold.",
            },
            {
              severity: "warning",
              reason: "Failure rate exceeds threshold.",
            },
          ],
        },
      });

    expect(candidates).toHaveLength(1);
  });
});
