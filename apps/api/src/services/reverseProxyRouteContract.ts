export type ReverseProxyRoute = {
  id: string;
  publicPath: string;
  upstream: string;
  websocket: boolean;
  required: boolean;
  description: string;
};

export type ReverseProxyRouteContract = {
  ready: boolean;
  routes: ReverseProxyRoute[];
  requirements: {
    preserveHost: boolean;
    forwardProto: boolean;
    forwardFor: boolean;
    websocketUpgrade: boolean;
    stripApiPrefix: boolean;
  };
};

export function getReverseProxyRouteContract():
  ReverseProxyRouteContract {
  const routes: ReverseProxyRoute[] = [
    {
      id:
        "dashboard",
      publicPath:
        "/",
      upstream:
        "http://dashboard:4000",
      websocket:
        false,
      required:
        true,
      description:
        "Public SportsOS dashboard and browser application.",
    },
    {
      id:
        "api",
      publicPath:
        "/api/",
      upstream:
        "http://api:4001/",
      websocket:
        false,
      required:
        true,
      description:
        "Public API path forwarded to the SportsOS API service.",
    },
    {
      id:
        "api-health",
      publicPath:
        "/api/health",
      upstream:
        "http://api:4001/health",
      websocket:
        false,
      required:
        true,
      description:
        "External API health verification.",
    },
    {
      id:
        "socket-io",
      publicPath:
        "/socket.io/",
      upstream:
        "http://api:4001/socket.io/",
      websocket:
        true,
      required:
        true,
      description:
        "Socket.IO realtime transport with HTTP upgrade support.",
    },
  ];

  return {
    ready:
      routes
        .filter(
          (route) =>
            route.required,
        )
        .every(
          (route) =>
            route.publicPath.length >
              0 &&
            route.upstream.length >
              0,
        ),
    routes,
    requirements: {
      preserveHost:
        true,
      forwardProto:
        true,
      forwardFor:
        true,
      websocketUpgrade:
        true,
      stripApiPrefix:
        true,
    },
  };
}
