"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import "./tournament-focus-panel.css";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

type FocusGame = {
  readonly id: number;
  readonly organizationName: string;
  readonly homeTeamName: string;
  readonly awayTeamName: string;
  readonly scheduledStart: string;
  readonly venue: string | null;
  readonly status: GameStatus;
};

type Props = {
  readonly games: readonly FocusGame[];
};

type Urgency = "ALL" | "LATE" | "STARTING_SOON" | "LIVE" | "NORMAL";

function urgencyFor(game: FocusGame, now: number): Exclude<Urgency, "ALL"> {
  if (game.status === "LIVE") return "LIVE";

  if (game.status === "SCHEDULED") {
    const deltaMs = new Date(game.scheduledStart).getTime() - now;

    if (deltaMs < -5 * 60_000) return "LATE";
    if (deltaMs <= 15 * 60_000) return "STARTING_SOON";
  }

  return "NORMAL";
}

function timeLabel(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    weekday: "short",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

export function TournamentFocusPanel({ games }: Props) {
  const [rink, setRink] = useState("ALL");
  const [organization, setOrganization] = useState("ALL");
  const [team, setTeam] = useState("ALL");
  const [urgency, setUrgency] = useState<Urgency>("ALL");

  const now = Date.now();

  const activeGames = useMemo(
    () =>
      games.filter(
        (game) => game.status !== "FINAL" && game.status !== "CANCELED",
      ),
    [games],
  );

  const rinks = useMemo(
    () =>
      Array.from(
        new Set(activeGames.map((game) => game.venue?.trim() || "Rink not assigned")),
      ).sort((left, right) => left.localeCompare(right)),
    [activeGames],
  );

  const organizations = useMemo(
    () =>
      Array.from(new Set(activeGames.map((game) => game.organizationName)))
        .filter(Boolean)
        .sort((left, right) => left.localeCompare(right)),
    [activeGames],
  );

  const teams = useMemo(
    () =>
      Array.from(
        new Set(
          activeGames.flatMap((game) => [
            game.homeTeamName,
            game.awayTeamName,
          ]),
        ),
      )
        .filter(Boolean)
        .sort((left, right) => left.localeCompare(right)),
    [activeGames],
  );

  const focusedGames = useMemo(
    () =>
      activeGames
        .filter((game) => {
          const gameRink = game.venue?.trim() || "Rink not assigned";
          const gameUrgency = urgencyFor(game, now);

          if (rink !== "ALL" && gameRink !== rink) return false;
          if (
            organization !== "ALL" &&
            game.organizationName !== organization
          ) {
            return false;
          }
          if (
            team !== "ALL" &&
            game.homeTeamName !== team &&
            game.awayTeamName !== team
          ) {
            return false;
          }
          if (urgency !== "ALL" && gameUrgency !== urgency) return false;

          return true;
        })
        .sort((left, right) => {
          const leftUrgency = urgencyFor(left, now);
          const rightUrgency = urgencyFor(right, now);

          const priority: Record<Exclude<Urgency, "ALL">, number> = {
            LATE: 0,
            LIVE: 1,
            STARTING_SOON: 2,
            NORMAL: 3,
          };

          const urgencyDelta =
            priority[leftUrgency] - priority[rightUrgency];

          if (urgencyDelta !== 0) return urgencyDelta;

          return (
            new Date(left.scheduledStart).getTime() -
            new Date(right.scheduledStart).getTime()
          );
        }),
    [activeGames, organization, rink, team, urgency, now],
  );

  const filtersActive =
    rink !== "ALL" ||
    organization !== "ALL" ||
    team !== "ALL" ||
    urgency !== "ALL";

  return (
    <section
      id="director-focus"
      data-testid="director-focus"
      className="tournamentFocusPanel"
      aria-labelledby="tournament-focus-heading"
    >
      <div className="tournamentFocusHeader">
        <div>
          <span className="tournamentFocusEyebrow">Focus mode</span>
          <h2 id="tournament-focus-heading">Narrow tournament operations</h2>
          <p>
            Filter active games by rink, organization, team, or urgency without
            changing the underlying tournament schedule.
          </p>
        </div>

        <div className="tournamentFocusCount">
          <strong>{focusedGames.length}</strong>
          <span>matching games</span>
        </div>
      </div>

      <div className="tournamentFocusFilters">
        <label>
          Rink
          <select value={rink} onChange={(event) => setRink(event.target.value)}>
            <option value="ALL">All rinks</option>
            {rinks.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </label>

        <label>
          Organization
          <select
            value={organization}
            onChange={(event) => setOrganization(event.target.value)}
          >
            <option value="ALL">All organizations</option>
            {organizations.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </label>

        <label>
          Team
          <select value={team} onChange={(event) => setTeam(event.target.value)}>
            <option value="ALL">All teams</option>
            {teams.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </label>

        <label>
          Urgency
          <select
            value={urgency}
            onChange={(event) => setUrgency(event.target.value as Urgency)}
          >
            <option value="ALL">All urgency</option>
            <option value="LATE">Late</option>
            <option value="STARTING_SOON">Starting soon</option>
            <option value="LIVE">Live</option>
            <option value="NORMAL">Normal</option>
          </select>
        </label>

        <button
          type="button"
          disabled={!filtersActive}
          onClick={() => {
            setRink("ALL");
            setOrganization("ALL");
            setTeam("ALL");
            setUrgency("ALL");
          }}
        >
          Clear filters
        </button>
      </div>

      {focusedGames.length === 0 ? (
        <div className="tournamentFocusEmpty">
          No active games match the current focus filters.
        </div>
      ) : (
        <div className="tournamentFocusGames" data-testid="director-focus-games">
          {focusedGames.map((game) => {
            const gameUrgency = urgencyFor(game, now);
            const gameRink = game.venue?.trim() || "Rink not assigned";

            return (
              <article
                key={game.id}
                className={`tournamentFocusGame urgency-${gameUrgency.toLowerCase()}`}
              >
                <div className="tournamentFocusGameMain">
                  <span className="tournamentFocusUrgency">
                    {gameUrgency.replaceAll("_", " ")}
                  </span>
                  <strong>
                    #{game.id} · {game.homeTeamName} vs {game.awayTeamName}
                  </strong>
                  <span>
                    {game.organizationName} · {gameRink} ·{" "}
                    {timeLabel(game.scheduledStart)}
                  </span>
                </div>

                <div className="tournamentFocusActions">
                  <Link href={`/games/${game.id}/control`}>Scorekeeper</Link>
                  <Link href={`/games/${game.id}/scoreboard`}>Scoreboard</Link>
                  <Link href={`/games/${game.id}/overlay`}>Overlay</Link>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}
