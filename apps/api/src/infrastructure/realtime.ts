import type { Server as HttpServer } from "node:http";
import { Server as SocketIOServer } from "socket.io";
import { config } from "@sportsos/config";
import {
  PERMISSIONS,
  assertPermission,
  identityFromToken,
  type AuthenticatedIdentity,
  type IdentityTokenPayload,
} from "../modules/auth/index.js";
import { findGameById } from "../modules/games/repository.js";
import { findScoreboardDeviceById } from "../modules/scoreboard-devices/repository.js";

let io: SocketIOServer | undefined;

export interface InitializeRealtimeOptions {
  readonly verifyToken: (token: string) => IdentityTokenPayload;
}

type SubscriptionScope = "game" | "scoreboard-device";

function positiveInteger(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function rejectSubscription(
  socket: {
    emit: (event: string, payload: unknown) => unknown;
  },
  scope: SubscriptionScope,
  id: number | null,
  reason: string,
): void {
  socket.emit("subscription:rejected", { scope, id, reason });
}

export function authorizeRealtimeOrganization(
  identity: AuthenticatedIdentity | null,
  organizationId: number,
  permission: typeof PERMISSIONS.GAME_READ | typeof PERMISSIONS.SCOREBOARD_READ,
): boolean {
  if (!identity) return false;

  try {
    assertPermission(identity, { permission, organizationId });
    return true;
  } catch {
    return false;
  }
}

export function initializeRealtime(
  server: HttpServer,
  options: InitializeRealtimeOptions,
): SocketIOServer {
  io = new SocketIOServer(server, {
    cors: { origin: config.dashboard.origin, credentials: true },
  });

  io.on("connection", (socket) => {
    let identity: AuthenticatedIdentity | null = null;
    const token =
      typeof socket.handshake.auth?.token === "string" ? socket.handshake.auth.token.trim() : "";

    if (token) {
      try {
        identity = identityFromToken(options.verifyToken(token));
      } catch {
        identity = null;
      }
    }

    socket.emit("system:hello", {
      message: "SportsOS realtime online",
      timestamp: new Date().toISOString(),
      authenticated: Boolean(identity),
    });

    socket.on("public-game:subscribe", async (payload: { gameId?: unknown }) => {
      const gameId = positiveInteger(payload?.gameId);
      if (!gameId) {
        rejectSubscription(socket, "game", null, "Invalid game id");
        return;
      }

      const game = await findGameById(gameId);
      if (!game) {
        rejectSubscription(socket, "game", gameId, "Game not found");
        return;
      }

      await socket.join(`game:${gameId}`);
    });

    socket.on("game:subscribe", async (payload: { gameId?: unknown }) => {
      const gameId = positiveInteger(payload?.gameId);
      if (!gameId) {
        rejectSubscription(socket, "game", null, "Invalid game id");
        return;
      }

      const game = await findGameById(gameId);
      if (!game) {
        rejectSubscription(socket, "game", gameId, "Game not found");
        return;
      }

      if (!authorizeRealtimeOrganization(identity, game.organizationId, PERMISSIONS.GAME_READ)) {
        rejectSubscription(socket, "game", gameId, "Game subscription denied");
        return;
      }

      await socket.join(`game:${gameId}`);
    });

    socket.on("scoreboard-device:subscribe", async (payload: { deviceId?: unknown }) => {
      const deviceId = positiveInteger(payload?.deviceId);
      if (!deviceId) {
        rejectSubscription(socket, "scoreboard-device", null, "Invalid device id");
        return;
      }

      const device = await findScoreboardDeviceById(deviceId);
      if (!device) {
        rejectSubscription(socket, "scoreboard-device", deviceId, "Device not found");
        return;
      }

      if (
        !authorizeRealtimeOrganization(identity, device.organizationId, PERMISSIONS.SCOREBOARD_READ)
      ) {
        rejectSubscription(
          socket,
          "scoreboard-device",
          deviceId,
          "Scoreboard device subscription denied",
        );
        return;
      }

      await socket.join(`scoreboard-device:${deviceId}`);
    });

    socket.on("game:leave", (payload: { gameId?: unknown }) => {
      const gameId = positiveInteger(payload?.gameId);
      if (!gameId) return;
      void socket.leave(`game:${gameId}`);
    });

    socket.on("scoreboard-device:leave", (payload: { deviceId?: unknown }) => {
      const deviceId = positiveInteger(payload?.deviceId);
      if (!deviceId) return;
      void socket.leave(`scoreboard-device:${deviceId}`);
    });
  });

  return io;
}

export function realtime(): SocketIOServer {
  if (!io) throw new Error("Realtime server has not been initialized");
  return io;
}
