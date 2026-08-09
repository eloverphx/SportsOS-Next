"use client";

import Link from "next/link";
import { useMemo } from "react";
import {
  DEFAULT_SCHEDULE_RULES,
  detectScheduleConflicts,
  type ScheduleGame,
} from "../../lib/tournament-schedule";
import "./tournament-schedule-conflicts.css";

type Props = {
  readonly games: readonly ScheduleGame[];
};

function conflictLabel(code: string): string {
  switch (code) {
    case "RINK_OVERLAP":
      return "Rink overlap";
    case "TEAM_OVERLAP":
      return "Team overlap";
    case "TEAM_TURNAROUND":
      return "Short turnaround";
    case "MISSING_RINK":
      return "Missing rink";
    default:
      return code;
  }
}

export function TournamentScheduleConflicts({ games }: Props) {
  const conflicts = useMemo(() => detectScheduleConflicts(games), [games]);
  const errors = conflicts.filter((conflict) => conflict.severity === "ERROR");
  const warnings = conflicts.filter((conflict) => conflict.severity === "WARNING");

  return (
    <section className="scheduleConflictPanel" aria-labelledby="schedule-conflicts-heading">
      <div className="scheduleConflictHeader">
        <div>
          <span className="scheduleConflictEyebrow">Schedule validation</span>
          <h2 id="schedule-conflicts-heading">Tournament schedule conflicts</h2>
          <p>
            Checks rink occupancy, duplicate team assignments, minimum turnaround,
            and missing rink assignments before tournament operations begin.
          </p>
        </div>

        <div className="scheduleConflictMetrics">
          <span className={errors.length > 0 ? "scheduleErrorCount" : ""}>
            Errors <strong>{errors.length}</strong>
          </span>
          <span className={warnings.length > 0 ? "scheduleWarningCount" : ""}>
            Warnings <strong>{warnings.length}</strong>
          </span>
        </div>
      </div>

      <div className="scheduleRuleSummary">
        Minimum team turnaround:{" "}
        <strong>{DEFAULT_SCHEDULE_RULES.minimumTeamTurnaroundMs / 60_000} minutes</strong>
        <span>·</span>
        Fallback game block:{" "}
        <strong>{DEFAULT_SCHEDULE_RULES.fallbackGameDurationMs / 60_000} minutes</strong>
      </div>

      {conflicts.length === 0 ? (
        <div className="scheduleClean">
          No schedule conflicts detected in the current active tournament games.
        </div>
      ) : (
        <div className="scheduleConflictList">
          {conflicts.map((conflict, index) => (
            <article
              key={`${conflict.code}-${conflict.gameId}-${conflict.relatedGameId ?? "none"}-${index}`}
              className={
                conflict.severity === "ERROR"
                  ? "scheduleConflict scheduleConflictError"
                  : "scheduleConflict scheduleConflictWarning"
              }
            >
              <div>
                <strong>{conflictLabel(conflict.code)}</strong>
                <span>{conflict.message}</span>
              </div>

              <div className="scheduleConflictActions">
                <Link href={`/games/${conflict.gameId}/control`}>
                  Game #{conflict.gameId}
                </Link>
                {conflict.relatedGameId ? (
                  <Link href={`/games/${conflict.relatedGameId}/control`}>
                    Game #{conflict.relatedGameId}
                  </Link>
                ) : null}
              </div>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
