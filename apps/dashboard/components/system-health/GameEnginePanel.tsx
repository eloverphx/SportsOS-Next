"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { authenticatedFetch } from "../../lib/authenticated-api";

interface GameEngineResponse {
  readonly status: "healthy" | "attention";
  readonly summary: {
    readonly total: number;
    readonly healthy: number;
    readonly transitionPending: number;
    readonly operatorRequired: number;
    readonly warnings: number;
  };
  readonly games: ReadonlyArray<{
    readonly gameId: number;
    readonly organizationId: number;
    readonly matchup: string;
    readonly state: "HEALTHY" | "TRANSITION_PENDING" | "OPERATOR_REQUIRED" | "WARNING";
    readonly status: string;
    readonly gamePhase: string;
    readonly period: number;
    readonly regulationPeriods: number;
    readonly clockRemainingMs: number;
    readonly clockRunning: boolean;
    readonly intermissionRemainingMs: number;
    readonly intermissionRunning: boolean;
    readonly actionRequired: string | null;
    readonly warnings: ReadonlyArray<{
      readonly code: string;
      readonly message: string;
    }>;
  }>;
  readonly recentTransitions: ReadonlyArray<{
    readonly timestamp: string;
    readonly source: "runtime-supervisor" | "system";
    readonly gameId: number;
    readonly action: string;
    readonly outcome: "applied" | "replayed" | "failed";
    readonly detail?: string;
  }>;
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function stateLabel(state: GameEngineResponse["games"][number]["state"]): string {
  switch (state) {
    case "HEALTHY":
      return "Healthy";
    case "TRANSITION_PENDING":
      return "Transition pending";
    case "OPERATOR_REQUIRED":
      return "Operator required";
    case "WARNING":
      return "Warning";
  }
}

export function GameEnginePanel() {
  const [telemetry, setTelemetry] = useState<GameEngineResponse | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async (): Promise<void> => {
    setError("");

    try {
      const response = await authenticatedFetch<GameEngineResponse>("/system/game-engine");
      setTelemetry(response);
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not load game engine telemetry",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();

    const timer = window.setInterval(() => {
      void load();
    }, 5_000);

    return () => window.clearInterval(timer);
  }, [load]);

  return (
    <section className="panel">
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          gap: 16,
          flexWrap: "wrap",
        }}
      >
        <div>
          <h2>Active Game Engine</h2>
          <p className="muted">
            Authoritative lifecycle state, automatic transitions, and operator warnings.
          </p>
        </div>

        <button className="secondary" disabled={loading} onClick={() => void load()}>
          {loading ? "Checking…" : "Refresh engine"}
        </button>
      </div>

      {error ? <p className="error">{error}</p> : null}

      {telemetry ? (
        <div className="cards" style={{ marginTop: 16 }}>
          <div className="metric">
            <span>Engine status</span>
            <strong className={telemetry.status === "healthy" ? "online" : "offline"}>
              {telemetry.status === "healthy" ? "Healthy" : "Attention needed"}
            </strong>
          </div>
          <div className="metric">
            <span>Visible games</span>
            <strong>{telemetry.summary.total}</strong>
          </div>
          <div className="metric">
            <span>Transition pending</span>
            <strong>{telemetry.summary.transitionPending}</strong>
          </div>
          <div className="metric">
            <span>Operator required</span>
            <strong>{telemetry.summary.operatorRequired}</strong>
          </div>
          <div className="metric">
            <span>Warnings</span>
            <strong>{telemetry.summary.warnings}</strong>
          </div>
        </div>
      ) : null}

      {!error && !telemetry && loading ? <p className="muted">Loading game engine…</p> : null}

      {telemetry?.games.length === 0 ? (
        <p className="muted">No scheduled or live games are currently visible.</p>
      ) : null}

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))",
          gap: 16,
          marginTop: 18,
        }}
      >
        {telemetry?.games.map((game) => (
          <article
            key={game.gameId}
            style={{
              border: "1px solid rgba(148, 163, 184, 0.24)",
              borderRadius: 14,
              padding: 16,
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "flex-start",
                gap: 12,
              }}
            >
              <div>
                <strong>{game.matchup}</strong>
                <div className="muted" style={{ marginTop: 4 }}>
                  Game #{game.gameId}
                </div>
              </div>
              <strong>{stateLabel(game.state)}</strong>
            </div>

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                gap: 12,
                marginTop: 16,
              }}
            >
              <div>
                <span className="muted">Phase</span>
                <div>{game.gamePhase}</div>
              </div>
              <div>
                <span className="muted">Period</span>
                <div>
                  {game.period} / {game.regulationPeriods}
                </div>
              </div>
              <div>
                <span className="muted">Game clock</span>
                <div>
                  {formatClock(game.clockRemainingMs)} {game.clockRunning ? "RUNNING" : "STOPPED"}
                </div>
              </div>
              <div>
                <span className="muted">Intermission</span>
                <div>
                  {formatClock(game.intermissionRemainingMs)}{" "}
                  {game.intermissionRunning ? "RUNNING" : "STOPPED"}
                </div>
              </div>
            </div>

            {game.actionRequired ? (
              <p style={{ marginTop: 14 }}>
                <strong>Action:</strong> {game.actionRequired}
              </p>
            ) : null}

            {game.warnings.length > 0 ? (
              <div style={{ marginTop: 14 }}>
                {game.warnings.map((warning) => (
                  <p className="error" key={warning.code}>
                    <strong>{warning.code}:</strong> {warning.message}
                  </p>
                ))}
              </div>
            ) : null}

            <div
              style={{
                display: "flex",
                gap: 12,
                flexWrap: "wrap",
                marginTop: 16,
              }}
            >
              <Link href={`/games/${game.gameId}/scoreboard`}>Open scoreboard</Link>
              <Link href={`/games/${game.gameId}/overlay`}>Open overlay</Link>
            </div>
          </article>
        ))}
      </div>

      <div style={{ marginTop: 24 }}>
        <h3>Recent engine transitions</h3>

        {telemetry?.recentTransitions.length === 0 ? (
          <p className="muted">No automatic lifecycle transitions recorded yet.</p>
        ) : null}

        <div className="activity">
          {telemetry?.recentTransitions.map((transition, index) => (
            <div
              key={`${transition.timestamp}-${transition.gameId}-${transition.action}-${index}`}
            >
              <b>
                Game #{transition.gameId} — {transition.action}
              </b>
              <span>
                {transition.outcome} · {new Date(transition.timestamp).toLocaleTimeString()}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
