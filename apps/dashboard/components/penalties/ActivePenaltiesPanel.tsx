"use client";

import { useEffect, useMemo, useState } from "react";
import { api } from "../../lib/api";

type Penalty = {
  id: number;
  side: "home" | "away";
  playerName: string | null;
  jerseyNumber: number | null;
  infraction: string;
  remainingMs: number;
  running: boolean;
  startedAt: string | null;
};

interface Props {
  gameId: number;
  homeTeamName: string;
  awayTeamName: string;
  canScore: boolean;
  refreshToken: number;
}

function effectiveRemaining(penalty: Penalty, now: number): number {
  if (!penalty.running || !penalty.startedAt) return penalty.remainingMs;
  return Math.max(0, penalty.remainingMs - (now - new Date(penalty.startedAt).getTime()));
}

function format(ms: number): string {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

export function ActivePenaltiesPanel(props: Props) {
  const [penalties, setPenalties] = useState<Penalty[]>([]);
  const [now, setNow] = useState(() => Date.now());
  const [error, setError] = useState("");

  async function load(): Promise<void> {
    try {
      const response = await api<{ penalties: Penalty[] }>(`/games/${props.gameId}/penalties`);
      setPenalties(response.penalties);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load penalties");
    }
  }

  useEffect(() => {
    void load();
  }, [props.gameId, props.refreshToken]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const active = useMemo(
    () => penalties.filter((penalty) => effectiveRemaining(penalty, now) > 0),
    [penalties, now],
  );

  async function clear(id: number): Promise<void> {
    await api(`/games/${props.gameId}/penalties/${id}`, {
      method: "DELETE",
    });
    await load();
  }

  return (
    <section className="activePenaltiesPanel">
      <div className="activePenaltiesHead">
        <div>
          <h2>Active penalties</h2>
          <p>Penalty clocks run and pause with the game clock.</p>
        </div>
      </div>

      <div className="activePenaltiesGrid">
        {active.map((penalty) => (
          <article key={penalty.id} className="activePenaltyCard">
            <span>{penalty.side === "home" ? props.homeTeamName : props.awayTeamName}</span>
            <strong>{format(effectiveRemaining(penalty, now))}</strong>
            <p>
              {penalty.jerseyNumber == null ? "" : `#${penalty.jerseyNumber} `}
              {penalty.playerName || "Unassigned"} · {penalty.infraction}
            </p>
            {props.canScore && <button onClick={() => void clear(penalty.id)}>Clear</button>}
          </article>
        ))}
      </div>

      {!active.length && <p>No active penalties.</p>}
      {error && <p className="gameEventsError">{error}</p>}
    </section>
  );
}
