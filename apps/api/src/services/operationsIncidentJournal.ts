import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";

export type OperationsIncidentSeverity = "warning" | "critical";
export type OperationsIncidentStatus =
  | "open"
  | "acknowledged"
  | "resolved";

export type OperationsIncidentSource =
  | "operations"
  | "recovery"
  | "reliability"
  | "health";

export interface OperationsIncidentEvent {
  readonly eventId: string;
  readonly incidentId: string;
  readonly timestamp: string;
  readonly type:
    | "opened"
    | "acknowledged"
    | "resolved"
    | "reopened"
    | "updated";
  readonly actor: string;
  readonly note: string | null;
  readonly payload: Record<string, unknown>;
}

export interface OperationsIncident {
  readonly id: string;
  readonly fingerprint: string;
  readonly source: OperationsIncidentSource;
  readonly severity: OperationsIncidentSeverity;
  readonly status: OperationsIncidentStatus;
  readonly title: string;
  readonly summary: string;
  readonly service: string | null;
  readonly firstSeenAt: string;
  readonly lastSeenAt: string;
  readonly acknowledgedAt: string | null;
  readonly acknowledgedBy: string | null;
  readonly resolvedAt: string | null;
  readonly resolvedBy: string | null;
  readonly occurrences: number;
  readonly metadata: Record<string, unknown>;
  readonly events: readonly OperationsIncidentEvent[];
}

export interface OperationsIncidentJournal {
  readonly schemaVersion: 1;
  readonly generatedAt: string;
  readonly incidents: readonly OperationsIncident[];
}

export interface OpenOperationsIncidentInput {
  readonly fingerprint: string;
  readonly source: OperationsIncidentSource;
  readonly severity: OperationsIncidentSeverity;
  readonly title: string;
  readonly summary: string;
  readonly service?: string | null;
  readonly metadata?: Record<string, unknown>;
  readonly observedAt?: string;
}

const DEFAULT_DATA_ROOT = path.resolve(process.cwd(), "data");
const DEFAULT_INCIDENT_ROOT = path.join(
  DEFAULT_DATA_ROOT,
  "operations-incidents",
);

function getIncidentRoot(): string {
  return process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR
    ? path.resolve(process.env.SPORTSOS_OPERATIONS_INCIDENT_DIR)
    : DEFAULT_INCIDENT_ROOT;
}

function getJournalPath(): string {
  return path.join(getIncidentRoot(), "incidents.json");
}

function nowIso(): string {
  return new Date().toISOString();
}

function normalizeFingerprint(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!normalized) {
    throw new Error("Operations incident fingerprint is required.");
  }
  return normalized;
}

function createId(prefix: string): string {
  return `${prefix}_${crypto.randomUUID()}`;
}

function emptyJournal(): OperationsIncidentJournal {
  return {
    schemaVersion: 1,
    generatedAt: nowIso(),
    incidents: [],
  };
}

function parseJournal(raw: string): OperationsIncidentJournal {
  const parsed = JSON.parse(raw) as Partial<OperationsIncidentJournal>;
  if (parsed.schemaVersion !== 1 || !Array.isArray(parsed.incidents)) {
    throw new Error("Invalid operations incident journal.");
  }

  return {
    schemaVersion: 1,
    generatedAt:
      typeof parsed.generatedAt === "string"
        ? parsed.generatedAt
        : nowIso(),
    incidents: parsed.incidents as OperationsIncident[],
  };
}

export async function readOperationsIncidentJournal(): Promise<OperationsIncidentJournal> {
  try {
    return parseJournal(await readFile(getJournalPath(), "utf8"));
  } catch (error) {
    const code =
      typeof error === "object" &&
      error !== null &&
      "code" in error
        ? String((error as { code?: unknown }).code ?? "")
        : "";

    if (code === "ENOENT") {
      return emptyJournal();
    }

    throw error;
  }
}

async function persistJournal(
  journal: OperationsIncidentJournal,
): Promise<void> {
  const root = getIncidentRoot();
  const target = getJournalPath();
  const temp = `${target}.tmp-${process.pid}-${Date.now()}`;

  await mkdir(root, { recursive: true });
  await writeFile(
    temp,
    `${JSON.stringify(journal, null, 2)}\n`,
    {
      encoding: "utf8",
      mode: 0o640,
    },
  );
  await rename(temp, target);
}

export async function listOperationsIncidents(): Promise<
  readonly OperationsIncident[]
> {
  const journal = await readOperationsIncidentJournal();

  return [...journal.incidents].sort((left, right) =>
    right.lastSeenAt.localeCompare(left.lastSeenAt),
  );
}

export async function findOperationsIncidentById(
  incidentId: string,
): Promise<OperationsIncident | null> {
  const journal = await readOperationsIncidentJournal();
  return (
    journal.incidents.find((incident) => incident.id === incidentId) ??
    null
  );
}

export async function openOrUpdateOperationsIncident(
  input: OpenOperationsIncidentInput,
): Promise<OperationsIncident> {
  const observedAt = input.observedAt ?? nowIso();
  const fingerprint = normalizeFingerprint(input.fingerprint);
  const journal = await readOperationsIncidentJournal();

  const existingIndex = journal.incidents.findIndex(
    (incident) => incident.fingerprint === fingerprint,
  );

  if (existingIndex >= 0) {
    const existing = journal.incidents[existingIndex];
    if (!existing) {
      throw new Error(
        "Operations incident index resolved without an incident.",
      );
    }

    const reopened = existing.status === "resolved";

    const event: OperationsIncidentEvent = {
      eventId: createId("evt"),
      incidentId: existing.id,
      timestamp: observedAt,
      type: reopened ? "reopened" : "updated",
      actor: "system",
      note: null,
      payload: {
        severity: input.severity,
        source: input.source,
        service: input.service ?? null,
      },
    };

    const updated: OperationsIncident = {
      ...existing,
      source: input.source,
      severity: input.severity,
      status: reopened ? "open" : existing.status,
      title: input.title,
      summary: input.summary,
      service: input.service ?? existing.service,
      lastSeenAt: observedAt,
      acknowledgedAt: reopened
        ? null
        : existing.acknowledgedAt,
      acknowledgedBy: reopened
        ? null
        : existing.acknowledgedBy,
      resolvedAt: reopened ? null : existing.resolvedAt,
      resolvedBy: reopened ? null : existing.resolvedBy,
      occurrences: existing.occurrences + 1,
      metadata: {
        ...existing.metadata,
        ...(input.metadata ?? {}),
      },
      events: [...existing.events, event],
    };

    const incidents = [...journal.incidents];
    incidents[existingIndex] = updated;

    await persistJournal({
      schemaVersion: 1,
      generatedAt: nowIso(),
      incidents,
    });

    return updated;
  }

  const incidentId = createId("inc");
  const event: OperationsIncidentEvent = {
    eventId: createId("evt"),
    incidentId,
    timestamp: observedAt,
    type: "opened",
    actor: "system",
    note: null,
    payload: {
      severity: input.severity,
      source: input.source,
      service: input.service ?? null,
    },
  };

  const created: OperationsIncident = {
    id: incidentId,
    fingerprint,
    source: input.source,
    severity: input.severity,
    status: "open",
    title: input.title,
    summary: input.summary,
    service: input.service ?? null,
    firstSeenAt: observedAt,
    lastSeenAt: observedAt,
    acknowledgedAt: null,
    acknowledgedBy: null,
    resolvedAt: null,
    resolvedBy: null,
    occurrences: 1,
    metadata: input.metadata ?? {},
    events: [event],
  };

  await persistJournal({
    schemaVersion: 1,
    generatedAt: nowIso(),
    incidents: [...journal.incidents, created],
  });

  return created;
}


// SPORTSOS_M34_6_INCIDENT_LIFECYCLE
export interface OperationsIncidentLifecycleInput {
  actor: string;
  note?: string | null;
  observedAt?: string;
}

async function mutateOperationsIncidentLifecycle(
  incidentId: string,
  target: "acknowledged" | "resolved",
  input: OperationsIncidentLifecycleInput,
): Promise<OperationsIncident | null> {
  const actor = input.actor.trim();
  if (!actor) {
    throw new Error("Operations incident lifecycle actor is required.");
  }

  const journal = await readOperationsIncidentJournal();
  const index = journal.incidents.findIndex(
    (incident) => incident.id === incidentId,
  );
  if (index < 0) return null;

  const existing = journal.incidents[index];
  if (!existing) {
    throw new Error("Operations incident index resolved without an incident.");
  }

  const timestamp = input.observedAt ?? new Date().toISOString();
  const note = input.note?.trim() || null;

  if (target === "acknowledged") {
    if (existing.status === "resolved") {
      throw new Error("Resolved operations incidents cannot be acknowledged.");
    }
    if (existing.status === "acknowledged") {
      return existing;
    }

    const updated: OperationsIncident = {
      ...existing,
      status: "acknowledged",
      acknowledgedAt: timestamp,
      acknowledgedBy: actor,
      events: [
        ...existing.events,
        {
          eventId: `evt_${crypto.randomUUID()}`,
          incidentId: existing.id,
          timestamp,
          type: "acknowledged",
          actor,
          note,
          payload: {},
        },
      ],
    };
    await persistJournal({
      ...journal,
      incidents: journal.incidents.map((incident, incidentIndex) =>
        incidentIndex === index ? updated : incident,
      ),
    });
    return updated;
  }

  if (existing.status === "resolved") {
    return existing;
  }

  const updated: OperationsIncident = {
    ...existing,
    status: "resolved",
    resolvedAt: timestamp,
    resolvedBy: actor,
    events: [
      ...existing.events,
      {
        eventId: `evt_${crypto.randomUUID()}`,
        incidentId: existing.id,
        timestamp,
        type: "resolved",
        actor,
        note,
        payload: {},
      },
    ],
  };
  await persistJournal({
    ...journal,
    incidents: journal.incidents.map((incident, incidentIndex) =>
      incidentIndex === index ? updated : incident,
    ),
  });
  return updated;
}

export async function acknowledgeOperationsIncident(
  incidentId: string,
  input: OperationsIncidentLifecycleInput,
): Promise<OperationsIncident | null> {
  return mutateOperationsIncidentLifecycle(incidentId, "acknowledged", input);
}

export async function resolveOperationsIncident(
  incidentId: string,
  input: OperationsIncidentLifecycleInput,
): Promise<OperationsIncident | null> {
  return mutateOperationsIncidentLifecycle(incidentId, "resolved", input);
}
