"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { api } from "../../lib/api";

type Side = "home" | "away";
type PlayerOption = {
  id: number;
  teamId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
};
type EventItem = {
  id: number;
  type: "GOAL" | "PENALTY";
  side: Side;
  period: number;
  clockRemainingMs: number;
  playerName: string | null;
  assist1PlayerName: string | null;
  assist2PlayerName: string | null;
  penaltyCode: string | null;
  penaltyMinutes: number | null;
  notes: string | null;
  voidedAt: string | null;
};
interface Props {
  gameId: number;
  homeTeamId: number | null;
  awayTeamId: number | null;
  homeTeamName: string;
  awayTeamName: string;
  canScore: boolean;
  refreshToken: number;
  onScoreChanged: () => Promise<void>;
}
function clock(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}
function label(player: PlayerOption): string {
  return `${player.jerseyNumber == null ? "" : `#${player.jerseyNumber} `}${
    player.preferredName || player.firstName
  } ${player.lastName}`;
}

export function GameEventsPanel(props: Props) {
  const [players, setPlayers] = useState<PlayerOption[]>([]);
  const [events, setEvents] = useState<EventItem[]>([]);
  const [side, setSide] = useState<Side>("home");
  const [type, setType] = useState<"GOAL" | "PENALTY">("GOAL");
  const [playerId, setPlayerId] = useState("");
  const [assist1, setAssist1] = useState("");
  const [assist2, setAssist2] = useState("");
  const [penaltyCode, setPenaltyCode] = useState("Tripping");
  const [penaltyMinutes, setPenaltyMinutes] = useState("2");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const pendingCreate = useRef<{
    actionId: string;
    payloadJson: string;
  } | null>(null);
  const pendingUndo = useRef(new Map<number, string>());

  const teamId = side === "home" ? props.homeTeamId : props.awayTeamId;
  const options = useMemo(
    () => players.filter((player) => player.teamId === teamId),
    [players, teamId],
  );

  async function load(): Promise<void> {
    const [p, e] = await Promise.all([
      api<{ players: PlayerOption[] }>(`/games/${props.gameId}/event-players`),
      api<{ events: EventItem[] }>(`/games/${props.gameId}/events`),
    ]);
    setPlayers(p.players);
    setEvents(e.events);
  }

  useEffect(() => {
    void load().catch((cause) =>
      setError(cause instanceof Error ? cause.message : "Could not load events"),
    );
  }, [props.gameId, props.refreshToken]);

  useEffect(() => {
    setPlayerId("");
    setAssist1("");
    setAssist2("");
  }, [side]);

  async function submit(event: React.FormEvent): Promise<void> {
    event.preventDefault();
    if (!props.canScore || busy) return;

    const payload =
      type === "GOAL"
        ? {
            type,
            side,
            playerId: playerId || null,
            assist1PlayerId: assist1 || null,
            assist2PlayerId: assist2 || null,
            notes: notes || null,
          }
        : {
            type,
            side,
            playerId: playerId || null,
            penaltyCode,
            penaltyMinutes: Number(penaltyMinutes),
            notes: notes || null,
          };

    const payloadJson = JSON.stringify(payload);
    const existing = pendingCreate.current;
    const actionId =
      existing?.payloadJson === payloadJson ? existing.actionId : crypto.randomUUID();

    pendingCreate.current = { actionId, payloadJson };

    setBusy(true);
    setError("");

    try {
      await api(`/games/${props.gameId}/events`, {
        method: "POST",
        body: JSON.stringify({ ...payload, actionId }),
      });

      pendingCreate.current = null;
      setPlayerId("");
      setAssist1("");
      setAssist2("");
      setNotes("");
      await Promise.all([load(), props.onScoreChanged()]);
    } catch (cause) {
      // Keep pendingCreate so an ambiguous network failure can be retried
      // with the exact same actionId instead of creating a duplicate event.
      setError(cause instanceof Error ? cause.message : "Could not save event");
    } finally {
      setBusy(false);
    }
  }

  async function undo(id: number): Promise<void> {
    if (!window.confirm("Undo this event?")) return;

    const actionId = pendingUndo.current.get(id) ?? crypto.randomUUID();
    pendingUndo.current.set(id, actionId);

    setBusy(true);
    setError("");

    try {
      await api(`/games/${props.gameId}/events/${id}`, {
        method: "DELETE",
        headers: {
          "x-action-id": actionId,
        },
      });

      pendingUndo.current.delete(id);
      await Promise.all([load(), props.onScoreChanged()]);
    } catch (cause) {
      // Keep the actionId for this event so a retry is a safe replay.
      setError(cause instanceof Error ? cause.message : "Could not undo event");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="gameEventsPanel">
      <form className="gameEventsEntry" onSubmit={submit}>
        <h2>Game event</h2>
        <div className="gameEventsTabs">
          <button
            type="button"
            className={type === "GOAL" ? "active" : ""}
            onClick={() => setType("GOAL")}
          >
            Goal
          </button>
          <button
            type="button"
            className={type === "PENALTY" ? "active" : ""}
            onClick={() => setType("PENALTY")}
          >
            Penalty
          </button>
        </div>
        <label>
          Team
          <select value={side} onChange={(e) => setSide(e.target.value as Side)}>
            <option value="home">{props.homeTeamName}</option>
            <option value="away">{props.awayTeamName}</option>
          </select>
        </label>
        <label>
          {type === "GOAL" ? "Scorer" : "Player"}
          <select value={playerId} onChange={(e) => setPlayerId(e.target.value)}>
            <option value="">Unassigned</option>
            {options.map((p) => (
              <option key={p.id} value={p.id}>
                {label(p)}
              </option>
            ))}
          </select>
        </label>
        {type === "GOAL" ? (
          <>
            <label>
              First assist
              <select value={assist1} onChange={(e) => setAssist1(e.target.value)}>
                <option value="">None</option>
                {options
                  .filter((p) => String(p.id) !== playerId)
                  .map((p) => (
                    <option key={p.id} value={p.id}>
                      {label(p)}
                    </option>
                  ))}
              </select>
            </label>
            <label>
              Second assist
              <select value={assist2} onChange={(e) => setAssist2(e.target.value)}>
                <option value="">None</option>
                {options
                  .filter((p) => String(p.id) !== playerId && String(p.id) !== assist1)
                  .map((p) => (
                    <option key={p.id} value={p.id}>
                      {label(p)}
                    </option>
                  ))}
              </select>
            </label>
          </>
        ) : (
          <>
            <label>
              Infraction
              <input
                required
                value={penaltyCode}
                onChange={(e) => setPenaltyCode(e.target.value)}
              />
            </label>
            <label>
              Minutes
              <select value={penaltyMinutes} onChange={(e) => setPenaltyMinutes(e.target.value)}>
                {[
                  ["1", "1:00"],
                  ["1.5", "1:30"],
                  ["2", "2:00"],
                  ["4", "4:00"],
                  ["5", "5:00"],
                  ["10", "10:00"],
                ].map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
          </>
        )}
        <label>
          Notes
          <input value={notes} onChange={(e) => setNotes(e.target.value)} />
        </label>
        <button disabled={!props.canScore || busy}>
          {busy ? "Saving…" : type === "GOAL" ? "Record goal" : "Record penalty"}
        </button>
        {teamId === null && (
          <p className="gameEventsNotice">
            External team: events may be entered without a roster player.
          </p>
        )}
        {error && <p className="gameEventsError">{error}</p>}
      </form>

      <div className="gameEventsHistory">
        <h2>Recent events</h2>
        {events.map((item) => (
          <article key={item.id} className={item.voidedAt ? "voided" : ""}>
            <div>
              <strong>
                {item.type === "GOAL" ? "GOAL" : `${item.penaltyMinutes} MIN PENALTY`}
              </strong>
              <span>
                P{item.period} · {clock(item.clockRemainingMs)}
              </span>
            </div>
            <p>
              {item.type === "GOAL"
                ? [
                    item.playerName || "Unassigned scorer",
                    item.assist1PlayerName ? `A1: ${item.assist1PlayerName}` : null,
                    item.assist2PlayerName ? `A2: ${item.assist2PlayerName}` : null,
                  ]
                    .filter(Boolean)
                    .join(" · ")
                : `${item.playerName || "Unassigned player"} · ${item.penaltyCode}`}
            </p>
            {item.notes && <p>{item.notes}</p>}
            {item.voidedAt ? (
              <span className="gameEventsVoided">VOIDED</span>
            ) : (
              props.canScore && (
                <button disabled={busy} onClick={() => void undo(item.id)}>
                  Undo
                </button>
              )
            )}
          </article>
        ))}
        {!events.length && <p>No game events recorded.</p>}
      </div>
    </section>
  );
}
