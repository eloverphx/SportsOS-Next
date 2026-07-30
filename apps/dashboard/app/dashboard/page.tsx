"use client";
import { useCallback, useEffect, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";
type Stats = {
  organizations: number;
  teams: number;
  players: number;
  activeGames: number;
  liveStreams: number;
};
type User = { firstName: string; organizationName: string };
type Event = { id: number; action: string; created_at: string };
export default function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [events, setEvents] = useState<Event[]>([]);
  const load = useCallback(() => {
    api<{ user: User }>("/auth/me").then((d) => setUser(d.user));
    api<Stats>("/dashboard/stats").then(setStats);
    api<{ events: Event[] }>("/audit/recent").then((d) => setEvents(d.events));
  }, []);
  useEffect(() => {
    load();
    const socket = io(API);
    [
      "organization:created",
      "organization:updated",
      "organization:deleted",
      "team:created",
      "team:updated",
      "team:deleted",
      "player:created",
      "player:updated",
      "player:deleted",
    ].forEach((e) => socket.on(e, load));
    const timer = setInterval(load, 30000);
    return () => {
      clearInterval(timer);
      socket.disconnect();
    };
  }, [load]);
  return (
    <AuthGate>
      <AppShell>
        <h1>Welcome{user?.firstName ? `, ${user.firstName}` : ""}</h1>
        <p className="muted">{user?.organizationName ?? "SportsOS"} operations overview</p>
        <div className="cards">
          <div className="metric">
            <span>Organizations</span>
            <b>{stats?.organizations ?? "—"}</b>
          </div>
          <div className="metric">
            <span>Teams</span>
            <b>{stats?.teams ?? "—"}</b>
          </div>
          <div className="metric">
            <span>Players</span>
            <b>{stats?.players ?? 0}</b>
          </div>
          <div className="metric">
            <span>Active games</span>
            <b>{stats?.activeGames ?? 0}</b>
          </div>
          <div className="metric">
            <span>Live streams</span>
            <b>{stats?.liveStreams ?? 0}</b>
          </div>
        </div>
        <section className="panel">
          <h2>Recent activity</h2>
          {events.length ? (
            <div className="activity">
              {events.slice(0, 8).map((e) => (
                <div key={e.id}>
                  <b>{e.action.replaceAll(".", " ")}</b>
                  <time>{new Date(e.created_at).toLocaleString()}</time>
                </div>
              ))}
            </div>
          ) : (
            <p>No activity yet.</p>
          )}
        </section>
      </AppShell>
    </AuthGate>
  );
}
