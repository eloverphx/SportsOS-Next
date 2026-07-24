import type { Server as HttpServer } from 'node:http';
import { Server as SocketIOServer } from 'socket.io';
import { env } from '../config/env.js';

let io: SocketIOServer | undefined;

export function initializeRealtime(server: HttpServer): SocketIOServer {
  io = new SocketIOServer(server, {
    cors: { origin: env.DASHBOARD_ORIGIN, credentials: true }
  });
  io.on('connection', (socket) => {
    socket.emit('system:hello', {
      message: 'SportsOS realtime online',
      timestamp: new Date().toISOString()
    });
  });
  return io;
}

export function realtime(): SocketIOServer {
  if (!io) throw new Error('Realtime server has not been initialized');
  return io;
}
