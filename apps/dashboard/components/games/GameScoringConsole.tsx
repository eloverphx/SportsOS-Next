"use client";

import { useEffect, useMemo, useState } from "react";

export type ScoringGameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
export type ScoringGamePhase = "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";

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
  regulationPeriods: number;
  regulationPeriodLengthMs: number;
  intermissionLengthMs: number;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  intermissionReady: boolean;
  overtimeEnabled: boolean;
  overtimeLengthMs: number;
  periodLabel: string;
  canAdvancePeriod: boolean;
  status: ScoringGameStatus;
  gamePhase: ScoringGamePhase;
}

export type ScoringAction =
  | { action: "adjustScore"; side: "home" | "away"; amount: number }
  | { action: "startClock" }
  | { action: "pauseClock" }
  | { action: "startIntermission" }
  | { action: "pauseIntermission" }
  | { action: "resetIntermission" }
  | { action: "setIntermission"; intermissionLengthMs: number }
  | { action: "skipIntermission" }
  | { action: "nextPeriod" }
  | { action: "startOvertime" }
  | { action: "finishGame" }
  | { action: "resetClock"; periodLengthMs?: number }
  | { action: "adjustClock"; amountMs: number }
  | { action: "setClock"; clockRemainingMs: number }
  | { action: "setPeriod"; period: number }
  | { action: "setStatus"; status: ScoringGameStatus };

interface Props {
  readonly game: ScoringGame;
  readonly busy: boolean;
  readonly error: string;
  readonly onAction: (action: ScoringAction) => Promise<void>;
  readonly onClose: () => void;
}

function remainingMs(game: ScoringGame, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) return Math.max(0, game.clockRemainingMs);
  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function intermissionMs(game: ScoringGame, now: number): number {
  if (!game.intermissionRunning || !game.intermissionStartedAt) {
    return Math.max(0, game.intermissionRemainingMs);
  }
  return Math.max(
    0,
    game.intermissionRemainingMs - (now - new Date(game.intermissionStartedAt).getTime()),
  );
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

export function GameScoringConsole({ game, busy, error, onAction, onClose }: Props) {
  const [now, setNow] = useState(() => Date.now());
  const [minutes, setMinutes] = useState("20");
  const [seconds, setSeconds] = useState("00");
  const [intermissionMinutes, setIntermissionMinutes] = useState("15");
  const [intermissionSeconds, setIntermissionSeconds] = useState("00");
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [showPeriodEndDialog, setShowPeriodEndDialog] = useState(false);

  const gameClock = useMemo(() => remainingMs(game, now), [game, now]);
  const breakClock = useMemo(() => intermissionMs(game, now), [game, now]);
  const showingIntermission = game.gamePhase === "INTERMISSION";
  const isFinal = game.gamePhase === "FINAL";
  const isPregame = game.gamePhase === "PREGAME";
  const isOvertime = game.gamePhase === "OVERTIME";
  const canUseGameClock = !busy && !isFinal && !showingIntermission;
  const canStartIntermission = !busy && !isFinal && !showingIntermission && gameClock === 0;
  const canAdvance = !busy && !isFinal && !showingIntermission && gameClock === 0;

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", close);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("keydown", close);
      document.body.style.overflow = previousOverflow;
    };
  }, [onClose]);

  useEffect(() => {
    const total = Math.ceil(remainingMs(game, Date.now()) / 1000);
    setMinutes(String(Math.floor(total / 60)));
    setSeconds(String(total % 60).padStart(2, "0"));
  }, [game.id, game.clockRemainingMs, game.clockStartedAt]);

  useEffect(() => {
    const total = Math.ceil(game.intermissionLengthMs / 1000);
    setIntermissionMinutes(String(Math.floor(total / 60)));
    setIntermissionSeconds(String(total % 60).padStart(2, "0"));
  }, [game.id, game.intermissionLengthMs]);

  async function setExactClock(): Promise<void> {
    const m = Number(minutes);
    const s = Number(seconds);
    if (!Number.isInteger(m) || m < 0 || !Number.isInteger(s) || s < 0 || s > 59) return;
    await onAction({ action: "setClock", clockRemainingMs: m * 60_000 + s * 1000 });
  }

  async function setExactIntermission(): Promise<void> {
    const m = Number(intermissionMinutes);
    const s = Number(intermissionSeconds);
    if (!Number.isInteger(m) || m < 0 || m > 60 || !Number.isInteger(s) || s < 0 || s > 59) return;
    await onAction({ action: "setIntermission", intermissionLengthMs: m * 60_000 + s * 1000 });
  }

  async function advance(): Promise<void> {
    if (!canAdvance) return;
    if (game.period >= game.regulationPeriods) {
      setShowPeriodEndDialog(true);
      return;
    }
    await onAction({ action: "nextPeriod" });
  }

  return (
    <div
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 10000,
        display: "grid",
        placeItems: "center",
        padding: 16,
        background: "rgba(2,6,23,.82)",
        backdropFilter: "blur(6px)",
      }}
    >
      <section
        className="panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="live-scoring-title"
        style={{
          width: "min(1180px, 100%)",
          maxHeight: "calc(100vh - 32px)",
          overflowY: "auto",
          boxShadow: "0 30px 90px rgba(0,0,0,.55)",
        }}
      >
        <div className="pageHead">
          <div>
            <h2 id="live-scoring-title">Live scoring</h2>
            <p className="muted">
              {game.awayTeamName} at {game.homeTeamName}
            </p>
            <p className="muted">Phase: {game.gamePhase.replace("_", " ")}</p>
          </div>
          <button type="button" className="secondary" onClick={onClose}>
            Close
          </button>
        </div>

        {error && (
          <p className="error" role="alert" aria-live="assertive">
            {error}
          </p>
        )}

        <div className="cards">
          <div className="metric">
            <span>{game.awayTeamName}</span>
            <b>{game.awayScore}</b>
            <div className="cardActions">
              <button
                type="button"
                disabled={busy}
                onClick={() => void onAction({ action: "adjustScore", side: "away", amount: -1 })}
              >
                −
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => void onAction({ action: "adjustScore", side: "away", amount: 1 })}
              >
                +
              </button>
            </div>
          </div>

          <div className="metric">
            <span>
              {showingIntermission ? "INTERMISSION" : (game.periodLabel ?? `PERIOD ${game.period}`)}
            </span>
            <b>{formatClock(showingIntermission ? breakClock : gameClock)}</b>
            <span>
              {showingIntermission
                ? breakClock === 0
                  ? "Ready for next period"
                  : game.intermissionRunning
                    ? "Running · penalties paused"
                    : "Paused · penalties paused"
                : `${game.clockRunning ? "Running" : "Paused"} · ${game.status}`}
            </span>
          </div>

          <div className="metric">
            <span>{game.homeTeamName}</span>
            <b>{game.homeScore}</b>
            <div className="cardActions">
              <button
                type="button"
                disabled={busy}
                onClick={() => void onAction({ action: "adjustScore", side: "home", amount: -1 })}
              >
                −
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => void onAction({ action: "adjustScore", side: "home", amount: 1 })}
              >
                +
              </button>
            </div>
          </div>
        </div>

        <div className="formActions">
          <button
            type="button"
            disabled={!canUseGameClock}
            onClick={() =>
              void onAction({ action: game.clockRunning ? "pauseClock" : "startClock" })
            }
          >
            {game.clockRunning ? "Pause clock" : "Start clock"}
          </button>
          <button
            type="button"
            className="secondary"
            disabled={!canAdvance}
            onClick={() => void advance()}
          >
            {game.period >= game.regulationPeriods ? "Regulation complete" : "Start next period"}
          </button>
        </div>

        <h3>Intermission</h3>
        <div
          style={{
            padding: 16,
            border: "1px solid #0f766e",
            borderRadius: 14,
            background: "rgba(15,118,110,.14)",
            marginBottom: 14,
          }}
        >
          <div className="formGrid">
            <label>
              Minutes
              <input
                type="number"
                min="0"
                max="60"
                value={intermissionMinutes}
                onChange={(event) => setIntermissionMinutes(event.target.value)}
              />
            </label>
            <label>
              Seconds
              <input
                type="number"
                min="0"
                max="59"
                value={intermissionSeconds}
                onChange={(event) => setIntermissionSeconds(event.target.value)}
              />
            </label>
          </div>
          <div className="formActions">
            <button
              type="button"
              disabled={!canUseGameClock}
              onClick={() => void setExactIntermission()}
            >
              Set intermission
            </button>
            <button
              type="button"
              disabled={showingIntermission ? busy : !canStartIntermission}
              onClick={() =>
                void onAction({
                  action: game.intermissionRunning ? "pauseIntermission" : "startIntermission",
                })
              }
            >
              {game.intermissionRunning ? "Pause intermission" : "Start intermission"}
            </button>
            <button
              type="button"
              className="secondary"
              disabled={busy || isFinal || !showingIntermission}
              onClick={() => void onAction({ action: "resetIntermission" })}
            >
              Reset intermission
            </button>
            <button
              type="button"
              className="secondary"
              disabled={busy || !showingIntermission}
              onClick={() => void onAction({ action: "skipIntermission" })}
            >
              Skip intermission
            </button>
          </div>
        </div>

        <button
          type="button"
          className="secondary"
          onClick={() => setShowAdvanced((value) => !value)}
        >
          {showAdvanced ? "Hide advanced controls" : "Show advanced controls"}
        </button>

        {showAdvanced && (
          <>
            <h3>Advanced clock correction</h3>
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
                  type="button"
                  className="secondary"
                  disabled={!canUseGameClock}
                  key={String(label)}
                  onClick={() => void onAction({ action: "adjustClock", amountMs: Number(amount) })}
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
            </div>

            <div className="formActions">
              <button
                type="button"
                disabled={!canUseGameClock}
                onClick={() => void setExactClock()}
              >
                Set clock
              </button>
              <button
                type="button"
                className="secondary"
                disabled={!canUseGameClock}
                onClick={() => void onAction({ action: "resetClock" })}
              >
                Reset clock
              </button>
              <button
                type="button"
                className="secondary"
                disabled={busy || game.period <= 1}
                onClick={() =>
                  void onAction({ action: "setPeriod", period: Math.max(1, game.period - 1) })
                }
              >
                Period −
              </button>
              <button
                type="button"
                className="secondary"
                disabled={busy}
                onClick={() => void onAction({ action: "setPeriod", period: game.period + 1 })}
              >
                Period +
              </button>
            </div>
          </>
        )}

        <div className="formActions">
          <button
            type="button"
            disabled={busy || isFinal || (!isPregame && game.status === "LIVE")}
            onClick={() => void onAction({ action: "setStatus", status: "LIVE" })}
          >
            Mark live
          </button>
          <button
            type="button"
            className="secondary"
            disabled={busy || isFinal}
            onClick={() => void onAction({ action: "finishGame" })}
          >
            Mark final
          </button>
        </div>

        {showPeriodEndDialog && (
          <div
            role="presentation"
            onMouseDown={(event) => {
              if (event.target === event.currentTarget) setShowPeriodEndDialog(false);
            }}
            style={{
              position: "fixed",
              inset: 0,
              zIndex: 10020,
              display: "grid",
              placeItems: "center",
              padding: 20,
              background: "rgba(2,6,23,.82)",
            }}
          >
            <section
              className="panel"
              role="dialog"
              aria-modal="true"
              aria-labelledby="desktop-period-end-title"
              style={{ width: "min(520px, 100%)" }}
            >
              <h2 id="desktop-period-end-title">Regulation complete</h2>
              <p>
                {game.awayTeamName} {game.awayScore} – {game.homeScore} {game.homeTeamName}
              </p>
              <div className="formActions">
                {game.overtimeEnabled && !isOvertime && game.gamePhase === "REGULATION" && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      setShowPeriodEndDialog(false);
                      void onAction({ action: "startOvertime" });
                    }}
                  >
                    Start overtime
                  </button>
                )}
                <button
                  type="button"
                  className="danger"
                  disabled={busy}
                  onClick={() => {
                    setShowPeriodEndDialog(false);
                    void onAction({ action: "finishGame" });
                  }}
                >
                  Mark game final
                </button>
                <button
                  type="button"
                  className="secondary"
                  onClick={() => setShowPeriodEndDialog(false)}
                >
                  Cancel
                </button>
              </div>
            </section>
          </div>
        )}
      </section>
    </div>
  );
}
