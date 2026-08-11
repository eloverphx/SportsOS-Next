"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "../../lib/api";
import {
  detectScheduleConflicts,
  type ScheduleConflict,
  type ScheduleGame,
} from "../../lib/tournament-schedule";
import "./tournament-schedule-audit.css";

type ScheduleAuditAction =
  | "game.schedule_create_conflict_blocked"
  | "game.schedule_create_conflict_overridden"
  | "game.schedule_conflict_blocked"
  | "game.schedule_conflict_overridden";

type ScheduleAuditConflict = {
  readonly code: string;
  readonly severity: string;
  readonly gameId: number | null;
  readonly relatedGameId: number | null;
  readonly message: string;
};

type ScheduleAuditEvent = {
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

type ScheduleAuditResponse = {
  readonly events: ScheduleAuditEvent[];
  readonly total: number;
  readonly limit: number;
  readonly offset: number;
};

type DecisionFilter = "ALL" | "BLOCKED" | "OVERRIDDEN";

const AUDIT_PAGE_SIZE = 25;

type Props = {
  readonly games: readonly ScheduleGame[];
};

type CurrentIncidentStatus =
  | "CURRENT_CONFLICT"
  | "RESOLVED"
  | "GAME_NOT_CREATED"
  | "GAME_NOT_FOUND";

function conflictTouchesGame(
  conflict: ScheduleConflict,
  gameId: number,
): boolean {
  return conflict.gameId === gameId || conflict.relatedGameId === gameId;
}

function currentIncidentStatus(
  event: ScheduleAuditEvent,
  games: readonly ScheduleGame[],
  currentConflicts: readonly ScheduleConflict[],
): CurrentIncidentStatus {
  if (!event.gameId) {
    return "GAME_NOT_CREATED";
  }

  if (!games.some((game) => game.id === event.gameId)) {
    return "GAME_NOT_FOUND";
  }

  return currentConflicts.some((conflict) =>
    conflictTouchesGame(conflict, event.gameId as number),
  )
    ? "CURRENT_CONFLICT"
    : "RESOLVED";
}

function statusLabel(status: CurrentIncidentStatus): string {
  switch (status) {
    case "CURRENT_CONFLICT":
      return "Conflict still present";
    case "RESOLVED":
      return "Conflict resolved";
    case "GAME_NOT_CREATED":
      return "No game record created";
    case "GAME_NOT_FOUND":
      return "Game no longer present";
  }
}

function eventKind(action: ScheduleAuditAction): "BLOCKED" | "OVERRIDDEN" {
  return action.endsWith("_overridden") ? "OVERRIDDEN" : "BLOCKED";
}

function eventTitle(event: ScheduleAuditEvent): string {
  const create = event.action.includes("create");
  const kind = eventKind(event.action);

  if (kind === "OVERRIDDEN") {
    return create
      ? "Conflicting game creation overridden"
      : "Schedule conflict overridden";
  }

  return create
    ? "Conflicting game creation blocked"
    : "Schedule change blocked";
}

function formatWhen(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export function TournamentScheduleAudit({ games }: Props) {
  const [events, setEvents] = useState<ScheduleAuditEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [decision, setDecision] = useState<DecisionFilter>("ALL");
  const [gameId, setGameId] = useState("");
  const [rink, setRink] = useState("ALL");
  const [actor, setActor] = useState("ALL");
  const [organizationId, setOrganizationId] = useState("ALL");
  const [serverTotal, setServerTotal] = useState(0);
  const [pageOffset, setPageOffset] = useState(0);
  const [debouncedGameId, setDebouncedGameId] = useState("");

  const currentConflicts = useMemo(
    () => detectScheduleConflicts(games),
    [games],
  );

  useEffect(() => {
    const timer = window.setTimeout(
      () => setDebouncedGameId(gameId.trim()),
      300,
    );

    return () => window.clearTimeout(timer);
  }, [gameId]);

  const selectedActorUserId = useMemo(() => {
    if (actor === "ALL") return null;

    return (
      events.find((event) => event.actorName === actor)?.actorUserId ?? null
    );
  }, [actor, events]);

  const load = useCallback(async () => {
    try {
      const params = new URLSearchParams({
        limit: String(AUDIT_PAGE_SIZE),
        offset: String(pageOffset),
      });

      if (decision !== "ALL") {
        params.set("decision", decision);
      }

      if (/^\d+$/.test(debouncedGameId)) {
        params.set("gameId", debouncedGameId);
      }

      if (rink !== "ALL") {
        params.set("venue", rink);
      }

      if (selectedActorUserId) {
        params.set("actorUserId", String(selectedActorUserId));
      }

      if (organizationId !== "ALL") {
        params.set("organizationId", organizationId);
      }

      const response = await api<ScheduleAuditResponse>(
        `/games/schedule-audit/recent?${params.toString()}`,
      );

      setEvents(response.events);
      setServerTotal(response.total);
      setError("");
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not load schedule decision history.",
      );
    } finally {
      setLoading(false);
    }
  }, [
    debouncedGameId,
    decision,
    organizationId,
    pageOffset,
    rink,
    selectedActorUserId,
  ]);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), 15_000);
    return () => window.clearInterval(timer);
  }, [load]);

  useEffect(() => {
    setPageOffset(0);
  }, [decision, debouncedGameId, rink, actor, organizationId]);

  const rinkOptions = useMemo(
    () =>
      Array.from(
        new Set(
          events
            .map((event) => event.venue?.trim())
            .filter((value): value is string => Boolean(value)),
        ),
      ).sort((left, right) => left.localeCompare(right)),
    [events],
  );

  const actorOptions = useMemo(
    () =>
      Array.from(
        new Set(events.map((event) => event.actorName).filter(Boolean)),
      ).sort((left, right) => left.localeCompare(right)),
    [events],
  );



  const organizationOptions = useMemo(
    () =>
      Array.from(
        new Set(
          events
            .map((event) => event.organizationId)
            .filter((value): value is number => value !== null),
        ),
      ).sort((left, right) => left - right),
    [events],
  );

  const incidentSummary = useMemo(() => {
    let active = 0;
    let resolved = 0;
    let overridden = 0;
    let blocked = 0;

    for (const event of events) {
      const status = currentIncidentStatus(event, games, currentConflicts);

      if (status === "CURRENT_CONFLICT") active += 1;
      if (status === "RESOLVED") resolved += 1;

      if (eventKind(event.action) === "OVERRIDDEN") {
        overridden += 1;
      } else {
        blocked += 1;
      }
    }

    return {
      total: serverTotal,
      active,
      resolved,
      overridden,
      blocked,
    };
  }, [currentConflicts, events, games, serverTotal]);

  const filteredEvents = events;

  const filtersActive =
    decision !== "ALL" ||
    gameId.trim() !== "" ||
    rink !== "ALL" ||
    actor !== "ALL" ||
    organizationId !== "ALL";

  return (
    <section
      id="director-audit"
      data-testid="director-audit"
      className="scheduleAuditPanel"
      aria-labelledby="schedule-audit-heading"
    >
      <div className="scheduleAuditHeader">
        <div>
          <span className="scheduleAuditEyebrow">Schedule governance</span>
          <h2 id="schedule-audit-heading">Schedule decision history</h2>
          <p>
            Recent hard-conflict blocks and approved overrides, including who
            made the decision and the recorded reason.
          </p>
        </div>

        <button type="button" onClick={() => void load()} disabled={loading}>
          {loading ? "Refreshing…" : "Refresh history"}
        </button>
      </div>

      <div
        className="scheduleAuditMetrics"
        data-testid="director-audit-summary-metrics"
      >
        <article>
          <span>Total decisions</span>
          <strong>{incidentSummary.total}</strong>
        </article>
        <article>
          <span>Still active</span>
          <strong>{incidentSummary.active}</strong>
        </article>
        <article>
          <span>Resolved</span>
          <strong>{incidentSummary.resolved}</strong>
        </article>
        <article>
          <span>Overrides</span>
          <strong>{incidentSummary.overridden}</strong>
        </article>
        <article>
          <span>Blocked</span>
          <strong>{incidentSummary.blocked}</strong>
        </article>
      </div>

      <div className="scheduleAuditFilters" data-testid="director-audit-filters">
        <label>
          Decision
          <select
            value={decision}
            onChange={(event) =>
              setDecision(event.target.value as DecisionFilter)
            }
          >
            <option value="ALL">All decisions</option>
            <option value="BLOCKED">Blocked only</option>
            <option value="OVERRIDDEN">Overridden only</option>
          </select>
        </label>

        <label>
          Game ID
          <input
            inputMode="numeric"
            pattern="[0-9]*"
            value={gameId}
            onChange={(event) => setGameId(event.target.value)}
            placeholder="Any game"
          />
        </label>

        <label>
          Rink
          <select value={rink} onChange={(event) => setRink(event.target.value)}>
            <option value="ALL">All rinks</option>
            {rinkOptions.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </label>

        <label>
          Actor
          <select
            value={actor}
            onChange={(event) => setActor(event.target.value)}
          >
            <option value="ALL">All actors</option>
            {actorOptions.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </label>

        <label>
          Organization
          <select
            value={organizationId}
            onChange={(event) => setOrganizationId(event.target.value)}
          >
            <option value="ALL">All organizations</option>
            {organizationOptions.map((value) => (
              <option key={value} value={String(value)}>
                Organization #{value}
              </option>
            ))}
          </select>
        </label>

        <button
          type="button"
          className="secondary"
          disabled={!filtersActive}
          onClick={() => {
            setDecision("ALL");
            setGameId("");
            setRink("ALL");
            setActor("ALL");
            setOrganizationId("ALL");
            setPageOffset(0);
          }}
        >
          Clear filters
        </button>
      </div>

      <div className="scheduleAuditSummary">
        <strong>{serverTotal}</strong>
        <span>
          matching decision{serverTotal === 1 ? "" : "s"}
          {filtersActive ? " after filters" : ""}
          {serverTotal > 0
            ? ` · showing ${pageOffset + 1}-${Math.min(
                pageOffset + events.length,
                serverTotal,
              )}`
            : ""}
        </span>
      </div>

      {error ? <div className="scheduleAuditError">{error}</div> : null}

      {!loading && !error && filteredEvents.length === 0 ? (
        <div className="scheduleAuditEmpty">
          {events.length === 0
            ? "No schedule conflict decisions have been recorded yet."
            : "No schedule decisions match the current filters."}
        </div>
      ) : null}

      {filteredEvents.length > 0 ? (
        <div className="scheduleAuditList" data-testid="director-audit-events">
          {filteredEvents.map((event) => {
            const kind = eventKind(event.action);
            const currentStatus = currentIncidentStatus(
              event,
              games,
              currentConflicts,
            );

            return (
              <article
                key={event.id}
                className={`scheduleAuditEvent ${kind.toLowerCase()}`}
              >
                <div className="scheduleAuditEventTop">
                  <span className={`scheduleAuditBadge ${kind.toLowerCase()}`}>
                    {kind}
                  </span>
                  <strong>{eventTitle(event)}</strong>
                  <time>{formatWhen(event.createdAt)}</time>
                </div>

                <div
                  className={`scheduleAuditCurrentStatus ${currentStatus.toLowerCase()}`}
                  data-testid={`director-audit-current-status-${event.id}`}
                >
                  <span>Current schedule</span>
                  <strong>{statusLabel(currentStatus)}</strong>
                </div>

                <div className="scheduleAuditMeta">
                  <span>
                    Actor: <strong>{event.actorName}</strong>
                    {event.actorRole ? ` · ${event.actorRole.replaceAll("_", " ")}` : ""}
                  </span>
                  {event.organizationId ? (
                    <span>Organization #{event.organizationId}</span>
                  ) : null}
                  {event.gameId ? (
                    <span>
                      Game <strong>#{event.gameId}</strong>
                    </span>
                  ) : null}
                  {event.venue ? <span>Rink: {event.venue}</span> : null}
                  {event.scheduledStart ? (
                    <span>Requested: {formatWhen(event.scheduledStart)}</span>
                  ) : null}
                  <span>
                    {event.conflictCount} conflict
                    {event.conflictCount === 1 ? "" : "s"}
                  </span>
                </div>

                {kind === "OVERRIDDEN" ? (
                  <div className="scheduleAuditReason">
                    <span>Override reason</span>
                    <p>{event.reason ?? "No reason was recorded."}</p>
                  </div>
                ) : null}

                {event.conflicts.length > 0 ? (
                  <details className="scheduleAuditEvidence">
                    <summary>
                      View conflict evidence ({event.conflicts.length})
                    </summary>

                    <div className="scheduleAuditEvidenceList">
                      {event.conflicts.map((conflict, index) => (
                        <article
                          key={`${event.id}-${conflict.code}-${index}`}
                          className="scheduleAuditEvidenceItem"
                        >
                          <div className="scheduleAuditEvidenceTop">
                            <strong>{conflict.code.replaceAll("_", " ")}</strong>
                            <span>{conflict.severity}</span>
                          </div>

                          <p>{conflict.message}</p>

                          <div className="scheduleAuditEvidenceMeta">
                            {conflict.gameId ? (
                              <>
                                <span>Game #{conflict.gameId}</span>
                                <a
                                  href={`#director-timeline-game-${conflict.gameId}`}
                                >
                                  View game in timeline
                                </a>
                              </>
                            ) : null}
                            {conflict.relatedGameId ? (
                              <>
                                <span>
                                  Related game #{conflict.relatedGameId}
                                </span>
                                <a
                                  href={`#director-timeline-game-${conflict.relatedGameId}`}
                                >
                                  View related game in timeline
                                </a>
                              </>
                            ) : null}
                          </div>
                        </article>
                      ))}
                    </div>
                  </details>
                ) : null}

                {event.gameId ? (
                  <div
                    className="scheduleAuditActions"
                    data-testid={`director-audit-actions-${event.id}`}
                  >
                    <Link href={`/games/${event.gameId}/control`}>
                      Open scorekeeper
                    </Link>
                    <Link href={`/games/${event.gameId}/scoreboard`}>
                      Open scoreboard
                    </Link>
                    <Link href={`/games/${event.gameId}/overlay`}>
                      Open overlay
                    </Link>
                    <a href={`#director-timeline-game-${event.gameId}`}>
                      View in schedule timeline
                    </a>
                  </div>
                ) : (
                  <div className="scheduleAuditNoGame">
                    This incident was recorded before a game record existed.
                  </div>
                )}
              </article>
            );
          })}
        </div>
      ) : null}

      <div
        className="scheduleAuditPagination"
        data-testid="director-audit-pagination"
      >
        <button
          type="button"
          className="secondary"
          disabled={pageOffset === 0 || loading}
          onClick={() =>
            setPageOffset((current) =>
              Math.max(0, current - AUDIT_PAGE_SIZE),
            )
          }
        >
          Previous
        </button>

        <span>
          {serverTotal === 0
            ? "No pages"
            : `Page ${Math.floor(pageOffset / AUDIT_PAGE_SIZE) + 1} of ${Math.max(
                1,
                Math.ceil(serverTotal / AUDIT_PAGE_SIZE),
              )}`}
        </span>

        <button
          type="button"
          className="secondary"
          disabled={
            loading ||
            pageOffset + AUDIT_PAGE_SIZE >= serverTotal
          }
          onClick={() =>
            setPageOffset((current) => current + AUDIT_PAGE_SIZE)
          }
        >
          Next
        </button>
      </div>
    </section>
  );
}
