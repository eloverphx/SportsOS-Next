import type { Server as HttpServer } from "node:http";
import { Server as SocketIOServer } from "socket.io";
import { config } from "@sportsos/config";

let io: SocketIOServer | undefined;

export function initializeRealtime(server: HttpServer): SocketIOServer {
  io = new SocketIOServer(server, {
    cors: { origin: config.dashboard.origin, credentials: true },
  });
  io.on("connection", (socket) => {
    socket.emit("system:hello", {
      message: "SportsOS realtime online",
      timestamp: new Date().toISOString(),
    });

    socket.on("game:join", (payload: { gameId?: unknown }) => {
      const gameId = Number(payload?.gameId);
      if (!Number.isInteger(gameId) || gameId <= 0) return;
      void socket.join(`game:${gameId}`);
    });

    socket.on("game:leave", (payload: { gameId?: unknown }) => {
      const gameId = Number(payload?.gameId);
      if (!Number.isInteger(gameId) || gameId <= 0) return;
      void socket.leave(`game:${gameId}`);
    });
  });
  return io;
}

export function realtime(): SocketIOServer {
  if (!io) throw new Error("Realtime server has not been initialized");
  return io;
}
