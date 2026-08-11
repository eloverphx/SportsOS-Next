"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  detectScheduleConflicts,
  type ScheduleConflict,
  type ScheduleGame,
} from "../../lib/tournament-schedule";
import "./tournament-schedule-timeline.css";

type Props = {
  readonly games: readonly ScheduleGame[];
};

const PIXELS_PER_HOUR = 180;
const MIN_BLOCK_WIDTH = 96;
const MINUTES_PER_TICK = 30;
const FALLBACK_GAME_DURATION_MS = 90 * 60_000;

function dayKey(value: string | number | Date): string {
  const date = value instanceof Date ? value : new Date(value);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function displayDay(key: string): string {
  return new Intl.DateTimeFormat(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(new Date(`${key}T12:00:00`));
}

function displayTime(value: string | number | Date): string {
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(value instanceof Date ? value : new Date(value));
}

function durationMs(game: ScheduleGame): number {
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

  return FALLBACK_GAME_DURATION_MS;
}

function floorToHalfHour(ms: number): number {
  const date = new Date(ms);
  date.setSeconds(0, 0);
  date.setMinutes(date.getMinutes() < 30 ? 0 : 30);
  return date.getTime();
}

function ceilToHalfHour(ms: number): number {
  const floored = floorToHalfHour(ms);
  return floored === ms ? ms : floored + MINUTES_PER_TICK * 60_000;
}

function timelineGameIdFromHash(hash: string): number | null {
  const match = /^#director-timeline-game-(\d+)$/.exec(hash);
  if (!match?.[1]) return null;

  const gameId = Number(match[1]);
  return Number.isSafeInteger(gameId) && gameId > 0 ? gameId : null;
}

function conflictForGame(
  gameId: number,
  conflicts: readonly ScheduleConflict[],
): "ERROR" | "WARNING" | null {
  const related = conflicts.filter(
    (conflict) =>
      conflict.gameId === gameId || conflict.relatedGameId === gameId,
  );

  if (related.some((conflict) => conflict.severity === "ERROR")) return "ERROR";
  if (related.some((conflict) => conflict.severity === "WARNING")) return "WARNING";
  return null;
}

export function TournamentScheduleTimeline({ games }: Props) {
  const activeGames = useMemo(
    () =>
      games
        .filter(
          (game) =>
            game.status !== "CANCELED" &&
            Number.isFinite(new Date(game.scheduledStart).getTime()),
        )
        .slice()
        .sort(
          (left, right) =>
            new Date(left.scheduledStart).getTime() -
            new Date(right.scheduledStart).getTime(),
        ),
    [games],
  );

  const availableDays = useMemo(
    () => Array.from(new Set(activeGames.map((game) => dayKey(game.scheduledStart)))),
    [activeGames],
  );

  const todayKey = dayKey(new Date());

  const [selectedDay, setSelectedDay] = useState(() => {
    if (availableDays.includes(todayKey)) return todayKey;
    return availableDays[0] ?? todayKey;
  });
  const [now, setNow] = useState(() => Date.now());
  const [targetGameId, setTargetGameId] = useState<number | null>(null);

  useEffect(() => {
    if (!availableDays.length) return;

    if (!availableDays.includes(selectedDay)) {
      setSelectedDay(
        availableDays.includes(todayKey) ? todayKey : (availableDays[0] ?? todayKey),
      );
    }
  }, [availableDays, selectedDay, todayKey]);

  useEffect(() => {
    function syncHashTarget(): void {
      const gameId = timelineGameIdFromHash(window.location.hash);
      setTargetGameId(gameId);

      if (!gameId) return;

      const game = activeGames.find((entry) => entry.id === gameId);
      if (!game) return;

      const targetDay = dayKey(game.scheduledStart);
      if (targetDay !== selectedDay) {
        setSelectedDay(targetDay);
      }
    }

    syncHashTarget();
    window.addEventListener("hashchange", syncHashTarget);

    return () => {
      window.removeEventListener("hashchange", syncHashTarget);
    };
  }, [activeGames, selectedDay]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const dayGames = useMemo(
    () => activeGames.filter((game) => dayKey(game.scheduledStart) === selectedDay),
    [activeGames, selectedDay],
  );

  useEffect(() => {
    if (!targetGameId) return;

    const targetGame = activeGames.find((game) => game.id === targetGameId);
    if (!targetGame || dayKey(targetGame.scheduledStart) !== selectedDay) return;

    const frame = window.requestAnimationFrame(() => {
      const element = document.getElementById(
        `director-timeline-game-${targetGameId}`,
      );

      element?.scrollIntoView({
        behavior: "smooth",
        block: "center",
        inline: "center",
      });
    });

    return () => window.cancelAnimationFrame(frame);
  }, [activeGames, selectedDay, targetGameId]);

  const conflicts = useMemo(
    () => detectScheduleConflicts(dayGames),
    [dayGames],
  );

  const rinks = useMemo(() => {
    const map = new Map<string, ScheduleGame[]>();

    for (const game of dayGames) {
      const rink = game.venue?.trim() || "Rink not assigned";
      const current = map.get(rink) ?? [];
      current.push(game);
      map.set(rink, current);
    }

    return Array.from(map.entries())
      .map(([rink, rinkGames]) => ({
        rink,
        games: rinkGames.sort(
          (left, right) =>
            new Date(left.scheduledStart).getTime() -
            new Date(right.scheduledStart).getTime(),
        ),
      }))
      .sort((left, right) => left.rink.localeCompare(right.rink));
  }, [dayGames]);

  const range = useMemo(() => {
    if (!dayGames.length) return null;

    const starts = dayGames.map((game) => new Date(game.scheduledStart).getTime());
    const ends = dayGames.map(
      (game) => new Date(game.scheduledStart).getTime() + durationMs(game),
    );

    const min = floorToHalfHour(Math.min(...starts) - 30 * 60_000);
    const max = ceilToHalfHour(Math.max(...ends) + 30 * 60_000);

    return {
      startMs: min,
      endMs: Math.max(max, min + 2 * 60 * 60_000),
    };
  }, [dayGames]);

  const ticks = useMemo(() => {
    if (!range) return [];

    const values: number[] = [];
    for (
      let value = range.startMs;
      value <= range.endMs;
      value += MINUTES_PER_TICK * 60_000
    ) {
      values.push(value);
    }
    return values;
  }, [range]);

  const totalWidth = range
    ? Math.max(
        720,
        ((range.endMs - range.startMs) / (60 * 60_000)) * PIXELS_PER_HOUR,
      )
    : 720;

  const showNow =
    range &&
    selectedDay === todayKey &&
    now >= range.startMs &&
    now <= range.endMs;

  const nowLeft = showNow
    ? ((now - range.startMs) / (range.endMs - range.startMs)) * totalWidth
    : 0;

  return (
    <section
      id="director-timeline"
      data-testid="director-timeline"
      className="tournamentTimelinePanel"
      aria-labelledby="tournament-timeline-heading"
    >
      <div className="tournamentTimelineHeader">
        <div>
          <span className="tournamentTimelineEyebrow">Schedule visualization</span>
          <h2 id="tournament-timeline-heading">Rink timeline</h2>
          <p>
            Read-only tournament-day view. Each block uses the game&apos;s configured
            expected duration and links directly to Scorekeeper.
          </p>
        </div>

        {availableDays.length > 0 ? (
          <label className="tournamentTimelineDaySelect">
            Tournament day
            <select
              value={selectedDay}
              onChange={(event) => setSelectedDay(event.target.value)}
            >
              {availableDays.map((key) => (
                <option key={key} value={key}>
                  {displayDay(key)}
                </option>
              ))}
            </select>
          </label>
        ) : null}
      </div>

      {dayGames.length === 0 || !range ? (
        <div className="tournamentTimelineEmpty">
          No active games are available for the selected tournament day.
        </div>
      ) : (
        <>
          <div className="tournamentTimelineLegend" aria-label="Timeline legend">
            <span><i className="scheduled" /> Scheduled</span>
            <span><i className="live" /> Live</span>
            <span><i className="final" /> Final</span>
            <span><i className="warning" /> Warning</span>
            <span><i className="error" /> Hard conflict</span>
          </div>

          <div className="tournamentTimelineScroller">
            <div
              className="tournamentTimelineCanvas"
              style={{ width: `${totalWidth + 170}px` }}
            >
              <div className="tournamentTimelineAxis">
                <div className="tournamentTimelineRinkLabel">Rink</div>
                <div
                  className="tournamentTimelineTimeAxis"
                  style={{ width: `${totalWidth}px` }}
                >
                  {ticks.map((tick) => {
                    const left =
                      ((tick - range.startMs) / (range.endMs - range.startMs)) *
                      totalWidth;

                    return (
                      <div
                        key={tick}
                        className="tournamentTimelineTick"
                        style={{ left: `${left}px` }}
                      >
                        <span>{displayTime(tick)}</span>
                      </div>
                    );
                  })}
                </div>
              </div>

              {rinks.map(({ rink, games: rinkGames }) => (
                <div className="tournamentTimelineRow" key={rink}>
                  <div className="tournamentTimelineRinkLabel">
                    <strong>{rink}</strong>
                    <small>{rinkGames.length} game{rinkGames.length === 1 ? "" : "s"}</small>
                  </div>

                  <div
                    className="tournamentTimelineTrack"
                    style={{ width: `${totalWidth}px` }}
                  >
                    {ticks.map((tick) => {
                      const left =
                        ((tick - range.startMs) / (range.endMs - range.startMs)) *
                        totalWidth;

                      return (
                        <i
                          key={tick}
                          className="tournamentTimelineGridLine"
                          style={{ left: `${left}px` }}
                          aria-hidden="true"
                        />
                      );
                    })}

                    {showNow ? (
                      <i
                        className="tournamentTimelineNow"
                        style={{ left: `${nowLeft}px` }}
                        aria-label={`Current time ${displayTime(now)}`}
                      />
                    ) : null}

                    {rinkGames.map((game) => {
                      const start = new Date(game.scheduledStart).getTime();
                      const end = start + durationMs(game);
                      const left =
                        ((start - range.startMs) /
                          (range.endMs - range.startMs)) *
                        totalWidth;
                      const width = Math.max(
                        MIN_BLOCK_WIDTH,
                        ((end - start) / (range.endMs - range.startMs)) * totalWidth,
                      );
                      const severity = conflictForGame(game.id, conflicts);

                      return (
                        <Link
                          id={`director-timeline-game-${game.id}`}
                          data-game-id={game.id}
                          key={game.id}
                          href={`/games/${game.id}/control`}
                          className={[
                            "tournamentTimelineGame",
                            `status-${game.status.toLowerCase()}`,
                            severity ? `conflict-${severity.toLowerCase()}` : "",
                            targetGameId === game.id ? "audit-target" : "",
                          ]
                            .filter(Boolean)
                            .join(" ")}
                          style={{
                            left: `${left}px`,
                            width: `${width}px`,
                          }}
                          title={`${displayTime(start)} · ${game.homeTeamName} vs ${game.awayTeamName}`}
                        >
                          <span className="tournamentTimelineGameTopline">
                            <strong>{displayTime(start)}</strong>
                            <small>#{game.id}</small>
                          </span>
                          <span className="tournamentTimelineMatchup">
                            {game.homeTeamName}
                            <b>vs</b>
                            {game.awayTeamName}
                          </span>
                          <span className="tournamentTimelineGameMeta">
                            {game.status}
                            {severity ? ` · ${severity === "ERROR" ? "CONFLICT" : "WARNING"}` : ""}
                          </span>
                        </Link>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </>
      )}
    </section>
  );
}
