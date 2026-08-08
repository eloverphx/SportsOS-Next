import type { RealtimeClientEvents, RealtimeServerEvents } from "@sportsos/core";
import { io, type Socket } from "socket.io-client";

export type SportsOSRealtimeSocket = Socket<RealtimeServerEvents, RealtimeClientEvents>;

export function createRealtimeSocket(
  url: string,
  options?: Parameters<typeof io>[1],
): SportsOSRealtimeSocket {
  return io(url, options) as SportsOSRealtimeSocket;
}
