"use client";
import { useEffect, useState } from "react";
import { io } from "socket.io-client";

type State = "online" | "offline" | "pending";
type Health = { status: string; services: Record<string, State>; uptime: number };
const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4001";

export function SystemStatus() {
  const [health, setHealth] = useState<Health | null>(null);
  const [realtime, setRealtime] = useState<State>("pending");
  useEffect(() => {
    const load = () =>
      fetch(`${apiUrl}/health`)
        .then((r) => r.json())
        .then(setHealth)
        .catch(() => setHealth(null));
    load();
    const timer = setInterval(load, 10000);
    const socket = io(apiUrl, { transports: ["websocket", "polling"] });
    socket.on("connect", () => setRealtime("online"));
    socket.on("disconnect", () => setRealtime("offline"));
    socket.on("connect_error", () => setRealtime("offline"));
    return () => {
      clearInterval(timer);
      socket.disconnect();
    };
  }, []);
  const services: Record<string, State> = health?.services ?? {
    mysql: "pending",
    redis: "pending",
    mqtt: "pending",
    minio: "pending",
  };
  services.realtime = realtime;
  return (
    <div className="grid">
      {Object.entries(services).map(([name, status]) => (
        <div className="card" key={name}>
          <span className={`dot ${status}`} />
          <strong>{name.toUpperCase()}</strong>
          <p>{status}</p>
        </div>
      ))}
    </div>
  );
}
