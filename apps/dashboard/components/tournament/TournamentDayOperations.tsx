"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { ScheduleGame } from "../../lib/tournament-schedule";
import "./tournament-day-operations.css";

type Device = {
  readonly id: number;
  readonly gameId: number | null;
  readonly name: string;
  readonly status: "ONLINE" | "OFFLINE";
};

type EngineGame = {
  readonly gameId: number;
  readonly state:
    | "HEALTHY"
    | "TRANSITION_PENDING"
    | "OPERATOR_REQUIRED"
    | "WARNING";
  readonly actionRequired: string | null;
  readonly detail?: string | null;
};

type Props = {
  readonly games: readonly ScheduleGame[];
  readonly devices: readonly Device[];
  readonly engineGames: readonly EngineGame[];
};

type OperationsIssue = {
  readonly key: string;
  readonly priority: number;
  readonly tone: "critical" | "warning" | "info";
  readonly title: string;
  readonly detail: string;
  readonly gameId: number | null;
  readonly rink: string | null;
};

function minutesUntil(start: string, now: number): number {
  return Math.round((new Date(start).getTime() - now) / 60_000);
}

function expectedDurationMs(game: ScheduleGame): number {
  const periods = game.regulationPeriods;
  const periodLength = game.regulationPeriodLengthMs;
  const intermission = game.intermissionLengthMs;

  if (
    typeof periods === "number" &&
    typeof periodLength === "number" &&
    typeof intermission === "number" &&
    periods > 0 &&
    periodLength > 0
  ) {
    return (
      periods * periodLength +
      Math.max(0, periods - 1) * intermission +
      (game.overtimeEnabled && typeof game.overtimeLengthMs === "number"
        ? Math.max(0, game.overtimeLengthMs)
        : 0)
    );
  }

  return 90 * 60_000;
}

export function TournamentDayOperations({
  games,
  devices,
  engineGames,
}: Props) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const issues = useMemo(() => {
    const next: OperationsIssue[] = [];

    for (const game of games) {
      const rink = game.venue?.trim() || "Rink not assigned";
      const delta = minutesUntil(game.scheduledStart, now);

      if (game.status === "SCHEDULED") {
        if (delta < -5) {
          next.push({
            key: `late-${game.id}`,
            priority: 100,
            tone: "critical",
            title: `Game #${game.id} is late`,
            detail: `${game.homeTeamName} vs ${game.awayTeamName} was scheduled ${
              Math.abs(delta)
            } minutes ago.`,
            gameId: game.id,
            rink,
          });
        } else if (delta <= 15) {
          next.push({
            key: `soon-${game.id}`,
            priority: 70,
            tone: "warning",
            title: `Game #${game.id} starts soon`,
            detail: `${game.homeTeamName} vs ${game.awayTeamName} starts in ${Math.max(
              0,
              delta,
            )} minutes at ${rink}.`,
            gameId: game.id,
            rink,
          });
        }
      }

      const assignedDevices = devices.filter((device) => device.gameId === game.id);
      const offlineDevices = assignedDevices.filter(
        (device) => device.status === "OFFLINE",
      );

      if (offlineDevices.length > 0) {
        next.push({
          key: `device-${game.id}`,
          priority: 95,
          tone: "critical",
          title: `Scoreboard offline for game #${game.id}`,
          detail: offlineDevices.map((device) => device.name).join(", "),
          gameId: game.id,
          rink,
        });
      }

      const engine = engineGames.find((entry) => entry.gameId === game.id);

      if (
        engine &&
        (engine.state === "OPERATOR_REQUIRED" ||
          engine.state === "TRANSITION_PENDING" ||
          engine.state === "WARNING")
      ) {
        next.push({
          key: `engine-${game.id}`,
          priority: engine.state === "OPERATOR_REQUIRED" ? 98 : 85,
          tone: engine.state === "OPERATOR_REQUIRED" ? "critical" : "warning",
          title: `Game #${game.id} engine: ${engine.state.replaceAll("_", " ")}`,
          detail:
            engine.detail ||
            engine.actionRequired ||
            "Game engine needs attention.",
          gameId: game.id,
          rink,
        });
      }
    }

    const byRink = new Map<string, ScheduleGame[]>();

    for (const game of games) {
      if (
        game.status === "CANCELED" ||
        game.status === "FINAL" ||
        !game.venue?.trim()
      ) {
        continue;
      }

      const rink = game.venue.trim();
      const list = byRink.get(rink) ?? [];
      list.push(game);
      byRink.set(rink, list);
    }

    for (const [rink, rinkGames] of byRink) {
      const ordered = rinkGames
        .slice()
        .sort(
          (left, right) =>
            new Date(left.scheduledStart).getTime() -
            new Date(right.scheduledStart).getTime(),
        );

      for (let index = 0; index < ordered.length - 1; index += 1) {
        const current = ordered[index];
        const upcoming = ordered[index + 1];

        if (!current || !upcoming) continue;

        const currentEnd =
          new Date(current.scheduledStart).getTime() + expectedDurationMs(current);
        const nextStart = new Date(upcoming.scheduledStart).getTime();
        const gapMinutes = Math.round((nextStart - currentEnd) / 60_000);

        if (gapMinutes >= 0 && gapMinutes <= 20) {
          next.push({
            key: `turnover-${rink}-${current.id}-${upcoming.id}`,
            priority: gapMinutes <= 10 ? 80 : 60,
            tone: gapMinutes <= 10 ? "warning" : "info",
            title: `${rink} turnover is tight`,
            detail: `${gapMinutes} minute gap between game #${current.id} and game #${upcoming.id}.`,
            gameId: upcoming.id,
            rink,
          });
        }
      }
    }

    return next.sort((left, right) => {
      if (left.priority !== right.priority) return right.priority - left.priority;
      return left.title.localeCompare(right.title);
    });
  }, [devices, engineGames, games, now]);

  const critical = issues.filter((issue) => issue.tone === "critical").length;
  const warning = issues.filter((issue) => issue.tone === "warning").length;
  const info = issues.filter((issue) => issue.tone === "info").length;

  return (
    <section
      id="director-attention"
      data-testid="director-attention"
      className="tournamentOpsPanel"
      aria-labelledby="tournament-ops-heading"
    >
      <div className="tournamentOpsHeader">
        <div>
          <span className="tournamentOpsEyebrow">Tournament day operations</span>
          <h2 id="tournament-ops-heading">Director attention queue</h2>
          <p>
            Prioritized operational issues from schedule timing, rink turnover,
            scoreboard health, and game-engine state.
          </p>
        </div>

        <div className="tournamentOpsCounts" aria-label="Attention counts">
          <span className="critical">{critical} critical</span>
          <span className="warning">{warning} warnings</span>
          <span>{info} notices</span>
        </div>
      </div>

      {issues.length === 0 ? (
        <div className="tournamentOpsClear">
          No immediate tournament-day issues detected.
        </div>
      ) : (
        <div className="tournamentOpsList">
          {issues.map((issue) => (
            <article
              key={issue.key}
              className={`tournamentOpsIssue ${issue.tone}`}
            >
              <div>
                <span className="tournamentOpsIssueTone">
                  {issue.tone === "critical"
                    ? "ACTION REQUIRED"
                    : issue.tone === "warning"
                      ? "WATCH"
                      : "NOTICE"}
                </span>
                <strong>{issue.title}</strong>
                <p>{issue.detail}</p>
                {issue.rink ? <small>{issue.rink}</small> : null}
              </div>

              {issue.gameId ? (
                <div className="tournamentOpsActions">
                  <Link href={`/games/${issue.gameId}/control`}>
                    Scorekeeper
                  </Link>
                  <Link href={`/games/${issue.gameId}/scoreboard`}>
                    Scoreboard
                  </Link>
                </div>
              ) : null}
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
