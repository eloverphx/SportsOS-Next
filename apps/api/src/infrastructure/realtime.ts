import type { Server as HttpServer } from 'node:http';
import { Server as SocketIOServer } from 'socket.io';
import { config } from '@sportsos/config';

let io: SocketIOServer | undefined;

export function initializeRealtime(server: HttpServer): SocketIOServer {
  io = new SocketIOServer(server, {
    cors: { origin: config.dashboard.origin, credentials: true }
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
