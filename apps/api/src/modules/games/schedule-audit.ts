import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";

export const SCHEDULE_AUDIT_ACTIONS = [
  "game.schedule_create_conflict_blocked",
  "game.schedule_create_conflict_overridden",
  "game.schedule_conflict_blocked",
  "game.schedule_conflict_overridden",
] as const;

export type ScheduleAuditAction = (typeof SCHEDULE_AUDIT_ACTIONS)[number];

export type ScheduleAuditConflict = {
  readonly code: string;
  readonly severity: string;
  readonly gameId: number | null;
  readonly relatedGameId: number | null;
  readonly message: string;
};

export type ScheduleAuditDecisionFilter =
  | "ALL"
  | "BLOCKED"
  | "OVERRIDDEN";

export type ScheduleAuditQuery = {
  readonly organizationId: number | null;
  readonly decision?: ScheduleAuditDecisionFilter;
  readonly gameId?: number | null;
  readonly venue?: string | null;
  readonly actorUserId?: number | null;
  readonly limit?: number;
  readonly offset?: number;
};

export type ScheduleAuditPage = {
  readonly events: readonly ScheduleAuditEvent[];
  readonly total: number;
  readonly limit: number;
  readonly offset: number;
};

export type ScheduleAuditEvent = {
  readonly id: number;
  readonly action: ScheduleAuditAction;
  readonly actorUserId: number | null;
  readonly actorName: string;
  readonly actorRole: string | null;
  readonly organizationId: number | null;
  readonly gameId: number | null;
  readonly scheduledStart: string | null;
  readonly venue: string | null;
  readonly reason: string | null;
  readonly conflictCount: number;
  readonly conflicts: readonly ScheduleAuditConflict[];
  readonly createdAt: string;
};

type AuditDetails = Record<string, unknown>;

function detailsObject(value: unknown): AuditDetails {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as AuditDetails;
  }

  if (typeof value === "string") {
    try {
      const parsed: unknown = JSON.parse(value);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? (parsed as AuditDetails)
        : {};
    } catch {
      return {};
    }
  }

  return {};
}

function optionalNumber(value: unknown): number | null {
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : null;
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function normalizeConflicts(
  details: AuditDetails,
): ScheduleAuditConflict[] {
  const source = Array.isArray(details.conflicts)
    ? details.conflicts
    : Array.isArray(details.scheduleConflicts)
      ? details.scheduleConflicts
      : [];

  return source
    .filter(
      (value): value is Record<string, unknown> =>
        Boolean(value) && typeof value === "object" && !Array.isArray(value),
    )
    .map((conflict) => ({
      code: optionalString(conflict.code) ?? "UNKNOWN",
      severity: optionalString(conflict.severity) ?? "UNKNOWN",
      gameId: optionalNumber(conflict.gameId),
      relatedGameId: optionalNumber(conflict.relatedGameId),
      message:
        optionalString(conflict.message) ??
        "No conflict description was recorded.",
    }));
}

function conflictsCount(details: AuditDetails): number {
  return Array.isArray(details.conflicts)
    ? details.conflicts.length
    : Array.isArray(details.scheduleConflicts)
      ? details.scheduleConflicts.length
      : 0;
}

function scheduleAuditDecisionActions(
  decision: ScheduleAuditDecisionFilter,
): readonly ScheduleAuditAction[] {
  if (decision === "BLOCKED") {
    return SCHEDULE_AUDIT_ACTIONS.filter((action) =>
      action.endsWith("_blocked"),
    );
  }

  if (decision === "OVERRIDDEN") {
    return SCHEDULE_AUDIT_ACTIONS.filter((action) =>
      action.endsWith("_overridden"),
    );
  }

  return SCHEDULE_AUDIT_ACTIONS;
}

function boundedScheduleAuditInteger(
  value: number | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (!Number.isSafeInteger(value)) return fallback;
  return Math.min(maximum, Math.max(minimum, value as number));
}

function scheduleAuditEventFromRow(row: RowDataPacket): ScheduleAuditEvent {
  const details = detailsObject(row.details);
  const firstName = optionalString(row.first_name);
  const lastName = optionalString(row.last_name);
  const actorName =
    [firstName, lastName].filter(Boolean).join(" ") ||
    "System / unknown user";

  return {
    id: Number(row.id),
    action: String(row.action) as ScheduleAuditAction,
    actorUserId: optionalNumber(row.user_id),
    actorName,
    actorRole: optionalString(row.role),
    organizationId: optionalNumber(details.organizationId),
    gameId: optionalNumber(details.gameId),
    scheduledStart:
      optionalString(details.scheduledStart) ??
      optionalString(details.requestedScheduledStart),
    venue:
      optionalString(details.venue) ??
      optionalString(details.requestedVenue),
    reason:
      optionalString(details.reason) ??
      optionalString(details.scheduleConflictOverrideReason),
    conflictCount: conflictsCount(details),
    conflicts: normalizeConflicts(details),
    createdAt: new Date(row.created_at as string | Date).toISOString(),
  };
}

export async function listRecentScheduleAuditEvents(
  organizationId: number | null,
  limit = 40,
): Promise<ScheduleAuditEvent[]> {
  const safeLimit = Math.min(100, Math.max(1, Math.trunc(limit)));

  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT
       a.id,
       a.user_id,
       a.action,
       a.details,
       a.created_at,
       u.first_name,
       u.last_name,
       u.role
     FROM audit_log a
     LEFT JOIN users u ON u.id = a.user_id
     WHERE a.action IN (?, ?, ?, ?)
     ORDER BY a.id DESC
     LIMIT ?`,
    [...SCHEDULE_AUDIT_ACTIONS, safeLimit * 4],
  );

  const events: ScheduleAuditEvent[] = [];

  for (const row of rows) {
    const details = detailsObject(row.details);
    const eventOrganizationId = optionalNumber(details.organizationId);

    if (
      organizationId !== null &&
      eventOrganizationId !== organizationId
    ) {
      continue;
    }

    const firstName = optionalString(row.first_name);
    const lastName = optionalString(row.last_name);
    const actorName =
      [firstName, lastName].filter(Boolean).join(" ") || "System / unknown user";

    events.push({
      id: Number(row.id),
      action: String(row.action) as ScheduleAuditAction,
      actorUserId: optionalNumber(row.user_id),
      actorName,
      actorRole: optionalString(row.role),
      organizationId: eventOrganizationId,
      gameId: optionalNumber(details.gameId),
      scheduledStart:
        optionalString(details.scheduledStart) ??
        optionalString(details.requestedScheduledStart),
      venue:
        optionalString(details.venue) ??
        optionalString(details.requestedVenue),
      reason:
        optionalString(details.reason) ??
        optionalString(details.scheduleConflictOverrideReason),
      conflictCount: conflictsCount(details),
      conflicts: normalizeConflicts(details),
      createdAt: new Date(row.created_at as string | Date).toISOString(),
    });

    if (events.length >= safeLimit) break;
  }

  return events;
}


export async function queryScheduleAuditEvents(
  query: ScheduleAuditQuery,
): Promise<ScheduleAuditPage> {
  const limit = boundedScheduleAuditInteger(query.limit, 40, 1, 100);
  const offset = boundedScheduleAuditInteger(query.offset, 0, 0, 10_000);
  const actions = scheduleAuditDecisionActions(query.decision ?? "ALL");

  const clauses: string[] = [
    `a.action IN (${actions.map(() => "?").join(", ")})`,
  ];
  const params: unknown[] = [...actions];

  if (query.organizationId !== null) {
    clauses.push(
      "CAST(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.organizationId')) AS UNSIGNED) = ?",
    );
    params.push(query.organizationId);
  }

  if (query.gameId !== null && query.gameId !== undefined) {
    clauses.push(
      "CAST(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.gameId')) AS UNSIGNED) = ?",
    );
    params.push(query.gameId);
  }

  if (query.venue) {
    clauses.push(
      "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.venue')), JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.requestedVenue'))) = ?",
    );
    params.push(query.venue);
  }

  if (query.actorUserId !== null && query.actorUserId !== undefined) {
    clauses.push("a.user_id = ?");
    params.push(query.actorUserId);
  }

  const where = clauses.join(" AND ");

  const [countRows] = await pool.query<RowDataPacket[]>(
    `SELECT COUNT(*) AS total
       FROM audit_log a
      WHERE ${where}`,
    params,
  );

  const total = Number(countRows[0]?.total ?? 0);

  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT
       a.id,
       a.user_id,
       a.action,
       a.details,
       a.created_at,
       u.first_name,
       u.last_name,
       u.role
     FROM audit_log a
     LEFT JOIN users u ON u.id = a.user_id
     WHERE ${where}
     ORDER BY a.id DESC
     LIMIT ?
     OFFSET ?`,
    [...params, limit, offset],
  );

  return {
    events: rows.map(scheduleAuditEventFromRow),
    total,
    limit,
    offset,
  };
}
