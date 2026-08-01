"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

type Game = {
  id: number;
  organizationName: string;
  seasonName: string;
  homeTeamName: string;
  awayTeamName: string;
  scheduledStart: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  period: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
};

const statuses: readonly GameStatus[] = ["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"];

function remainingMs(game: Game, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) {
    return Math.max(0, game.clockRemainingMs);
  }
  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

export default function ScoreboardsPage() {
  const [games, setGames] = useState<Game[]>([]);
  const [statusFilter, setStatusFilter] = useState("");
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [copied, setCopied] = useState<number | null>(null);
  const [now, setNow] = useState(() => Date.now());

  const load = useCallback(async () => {
    try {
      const response = await api<{ games: Game[] }>("/games");
      setGames(response.games);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load scoreboards");
    }
  }, []);

  useEffect(() => {
    void load();
    const socket = io(API);
    ["game:created", "game:updated", "game:deleted", "game:scored"].forEach((eventName) =>
      socket.on(eventName, load),
    );
    return () => {
      socket.disconnect();
    };
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const filteredGames = useMemo(
    () =>
      games.filter((game) => {
        const text =
          `${game.homeTeamName} ${game.awayTeamName} ${game.organizationName} ${game.venue ?? ""}`.toLowerCase();
        return (
          (!statusFilter || game.status === statusFilter) &&
          text.includes(search.trim().toLowerCase())
        );
      }),
    [games, search, statusFilter],
  );

  async function copyUrl(gameId: number): Promise<void> {
    try {
      await navigator.clipboard.writeText(`${window.location.origin}/games/${gameId}/scoreboard`);
      setCopied(gameId);
      window.setTimeout(() => setCopied(null), 1800);
    } catch {
      setError("Could not copy scoreboard URL.");
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Scoreboards</h1>
            <p className="muted">Open, monitor, and share realtime scoreboard displays.</p>
          </div>

          <div className="filters">
            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              <option value="">All statuses</option>
              {statuses.map((status) => (
                <option key={status} value={status}>
                  {status}
                </option>
              ))}
            </select>

            <input
              className="search"
              placeholder="Search scoreboards"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
        </div>

        {error && <p className="error">{error}</p>}

        <div className="scoreboardWorkspaceGrid">
          {filteredGames.map((game) => (
            <article className="scoreboardWorkspaceCard" key={game.id}>
              <div className="scoreboardWorkspaceHead">
                <div>
                  <span className="eyebrow">{game.organizationName}</span>
                  <h2>
                    {game.awayTeamName} at {game.homeTeamName}
                  </h2>
                </div>
                <span className={game.status === "LIVE" ? "badge" : "badge off"}>
                  {game.status}
                </span>
              </div>

              <div className="scoreboardWorkspacePreview">
                <div>
                  <span>{game.awayTeamName}</span>
                  <b>{game.awayScore}</b>
                </div>
                <div className="scoreboardWorkspaceClock">
                  <span>Period {game.period}</span>
                  <b>{formatClock(remainingMs(game, now))}</b>
                  <small>{game.clockRunning ? "Running" : "Paused"}</small>
                </div>
                <div>
                  <span>{game.homeTeamName}</span>
                  <b>{game.homeScore}</b>
                </div>
              </div>

              <p className="muted">
                {new Date(game.scheduledStart).toLocaleString()} · {game.seasonName}
              </p>
              <p className="muted">{game.venue || "Venue not set"}</p>

              <div className="cardActions">
                <Link
                  href={`/games/${game.id}/scoreboard`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Open scoreboard
                </Link>
                <button className="secondary" onClick={() => void copyUrl(game.id)}>
                  {copied === game.id ? "Copied" : "Copy URL"}
                </button>
                <Link className="secondary" href="/games">
                  Open controls
                </Link>
              </div>
            </article>
          ))}
        </div>

        {!filteredGames.length && (
          <section className="panel">
            <p>No scoreboards match the current filters.</p>
          </section>
        )}
      </AppShell>
    </AuthGate>
  );
}
