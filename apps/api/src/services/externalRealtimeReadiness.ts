export type ExternalRealtimeReadiness = {
  ready: boolean;
  websocketUrl: string | null;
  socketIoPollingUrl: string | null;
  checks: Array<{
    id: string;
    ok: boolean;
    required: boolean;
    message: string;
  }>;
};

function parseHttpsOrigin(
  value: string | undefined,
): URL | null {
  if (!value) return null;

  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}

export function evaluateExternalRealtimeReadiness(
  env: Record<string, string | undefined>,
): ExternalRealtimeReadiness {
  const dashboard =
    parseHttpsOrigin(env.DASHBOARD_ORIGIN);

  const baseOrigin =
    dashboard?.origin ?? null;

  const websocketUrl =
    baseOrigin
      ? baseOrigin.replace(/^https:/, "wss:") +
        "/socket.io/?EIO=4&transport=websocket"
      : null;

  const socketIoPollingUrl =
    baseOrigin
      ? `${baseOrigin}/socket.io/?EIO=4&transport=polling`
      : null;

  const checks = [
    {
      id: "realtime:https-origin",
      ok: Boolean(dashboard),
      required: true,
      message:
        "DASHBOARD_ORIGIN must use https:// for external realtime readiness.",
    },
    {
      id: "realtime:wss-target",
      ok: Boolean(websocketUrl?.startsWith("wss://")),
      required: true,
      message:
        "External Socket.IO WebSocket target must use wss://.",
    },
    {
      id: "realtime:socket-io-path",
      ok: Boolean(websocketUrl?.includes("/socket.io/")),
      required: true,
      message:
        "External realtime route must preserve /socket.io/.",
    },
  ];

  return {
    ready: checks
      .filter((check) => check.required)
      .every((check) => check.ok),
    websocketUrl,
    socketIoPollingUrl,
    checks,
  };
}
