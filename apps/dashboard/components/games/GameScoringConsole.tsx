"use client";

import { useEffect, useMemo, useState } from "react";

export type ScoringGameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

export interface ScoringGame {
  id: number;
  homeTeamName: string;
  awayTeamName: string;
  homeScore: number;
  awayScore: number;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  status: ScoringGameStatus;
}

export type ScoringAction =
  | { action: "adjustScore"; side: "home" | "away"; amount: number }
  | { action: "startClock" }
  | { action: "pauseClock" }
  | { action: "resetClock"; periodLengthMs?: number }
  | { action: "adjustClock"; amountMs: number }
  | { action: "setClock"; clockRemainingMs: number }
  | { action: "setPeriod"; period: number }
  | { action: "setStatus"; status: ScoringGameStatus };

interface GameScoringConsoleProps {
  readonly game: ScoringGame;
  readonly busy: boolean;
  readonly onAction: (action: ScoringAction) => Promise<void>;
  readonly onClose: () => void;
}

function remainingMs(game: ScoringGame, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) {
    return Math.max(0, game.clockRemainingMs);
  }

  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function GameScoringConsole({ game, busy, onAction, onClose }: GameScoringConsoleProps) {
  const [now, setNow] = useState(() => Date.now());
  const [minutes, setMinutes] = useState("20");
  const [seconds, setSeconds] = useState("00");
  const displayedRemaining = useMemo(() => remainingMs(game, now), [game, now]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    const totalSeconds = Math.ceil(remainingMs(game, Date.now()) / 1000);
    setMinutes(String(Math.floor(totalSeconds / 60)));
    setSeconds(String(totalSeconds % 60).padStart(2, "0"));
  }, [game.id]);

  async function setExactClock(): Promise<void> {
    const minuteValue = Number(minutes);
    const secondValue = Number(seconds);

    if (
      !Number.isInteger(minuteValue) ||
      minuteValue < 0 ||
      !Number.isInteger(secondValue) ||
      secondValue < 0 ||
      secondValue > 59
    ) {
      return;
    }

    await onAction({
      action: "setClock",
      clockRemainingMs: minuteValue * 60_000 + secondValue * 1000,
    });
  }

  return (
    <section className="panel">
      <div className="pageHead">
        <div>
          <h2>Live scoring</h2>
          <p className="muted">
            {game.awayTeamName} at {game.homeTeamName}
          </p>
        </div>

        <button className="secondary" onClick={onClose}>
          Close
        </button>
      </div>

      <div className="cards">
        <div className="metric">
          <span>{game.awayTeamName}</span>
          <b>{game.awayScore}</b>
          <div className="cardActions">
            <button
              disabled={busy}
              onClick={() =>
                void onAction({
                  action: "adjustScore",
                  side: "away",
                  amount: -1,
                })
              }
            >
              −
            </button>
            <button
              disabled={busy}
              onClick={() =>
                void onAction({
                  action: "adjustScore",
                  side: "away",
                  amount: 1,
                })
              }
            >
              +
            </button>
          </div>
        </div>

        <div className="metric">
          <span>Period {game.period}</span>
          <b>{formatClock(displayedRemaining)}</b>
          <span>{game.clockRunning ? "Running" : "Paused"}</span>
        </div>

        <div className="metric">
          <span>{game.homeTeamName}</span>
          <b>{game.homeScore}</b>
          <div className="cardActions">
            <button
              disabled={busy}
              onClick={() =>
                void onAction({
                  action: "adjustScore",
                  side: "home",
                  amount: -1,
                })
              }
            >
              −
            </button>
            <button
              disabled={busy}
              onClick={() =>
                void onAction({
                  action: "adjustScore",
                  side: "home",
                  amount: 1,
                })
              }
            >
              +
            </button>
          </div>
        </div>
      </div>

      <div className="formActions">
        <button
          disabled={busy}
          onClick={() =>
            void onAction({
              action: game.clockRunning ? "pauseClock" : "startClock",
            })
          }
        >
          {game.clockRunning ? "Pause clock" : "Start clock"}
        </button>

        <button
          className="secondary"
          disabled={busy}
          onClick={() => void onAction({ action: "resetClock" })}
        >
          Reset clock
        </button>

        <button
          className="secondary"
          disabled={busy || game.period <= 1}
          onClick={() =>
            void onAction({
              action: "setPeriod",
              period: Math.max(1, game.period - 1),
            })
          }
        >
          Period −
        </button>

        <button
          className="secondary"
          disabled={busy}
          onClick={() =>
            void onAction({
              action: "setPeriod",
              period: game.period + 1,
            })
          }
        >
          Period +
        </button>
      </div>

      <h3>Realtime clock adjustments</h3>

      <div className="formActions">
        {[
          ["−1m", -60_000],
          ["+1m", 60_000],
          ["−10s", -10_000],
          ["+10s", 10_000],
          ["−1s", -1_000],
          ["+1s", 1_000],
        ].map(([label, amount]) => (
          <button
            className="secondary"
            disabled={busy}
            key={String(label)}
            onClick={() =>
              void onAction({
                action: "adjustClock",
                amountMs: Number(amount),
              })
            }
          >
            {label}
          </button>
        ))}
      </div>

      <div className="formGrid">
        <label>
          Minutes
          <input
            type="number"
            min="0"
            max="120"
            value={minutes}
            onChange={(event) => setMinutes(event.target.value)}
          />
        </label>

        <label>
          Seconds
          <input
            type="number"
            min="0"
            max="59"
            value={seconds}
            onChange={(event) => setSeconds(event.target.value)}
          />
        </label>

        <div className="formActions">
          <button disabled={busy} onClick={() => void setExactClock()}>
            Set clock
          </button>
        </div>
      </div>

      <div className="formActions">
        <button
          disabled={busy}
          onClick={() => void onAction({ action: "setStatus", status: "LIVE" })}
        >
          Mark live
        </button>

        <button
          className="secondary"
          disabled={busy}
          onClick={() => void onAction({ action: "setStatus", status: "FINAL" })}
        >
          Mark final
        </button>
      </div>
    </section>
  );
}
