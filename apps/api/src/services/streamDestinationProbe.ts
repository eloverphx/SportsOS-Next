import net from "node:net";

export type StreamDestinationProbeResult = {
  reachable: boolean;
  host: string | null;
  port: number | null;
  checkedAt: string;
  latencyMs: number | null;
  error: string | null;
};

function defaultPort(
  protocol: "RTMP" | "SRT",
  url: URL,
): number {
  if (url.port) {
    return Number(url.port);
  }

  if (protocol === "RTMP") {
    return 1935;
  }

  return 9000;
}

export async function probeStreamDestination(input: {
  protocol: "RTMP" | "SRT";
  ingestUrl: string;
  timeoutMs?: number;
}): Promise<StreamDestinationProbeResult> {
  const checkedAt =
    new Date().toISOString();

  let parsed: URL;

  try {
    parsed =
      new URL(
        input.ingestUrl,
      );
  } catch {
    return {
      reachable: false,
      host: null,
      port: null,
      checkedAt,
      latencyMs: null,
      error:
        "Invalid ingest URL.",
    };
  }

  const host =
    parsed.hostname;

  const port =
    defaultPort(
      input.protocol,
      parsed,
    );

  const timeoutMs =
    Math.max(
      500,
      Math.min(
        input.timeoutMs ??
          3000,
        10000,
      ),
    );

  const startedAt =
    Date.now();

  return await new Promise(
    (resolve) => {
      const socket =
        net.createConnection({
          host,
          port,
        });

      let settled =
        false;

      function finish(
        result:
          StreamDestinationProbeResult,
      ) {
        if (settled) {
          return;
        }

        settled =
          true;

        socket.destroy();

        resolve(
          result,
        );
      }

      socket.setTimeout(
        timeoutMs,
      );

      socket.once(
        "connect",
        () => {
          finish({
            reachable:
              true,
            host,
            port,
            checkedAt,
            latencyMs:
              Date.now() -
              startedAt,
            error:
              null,
          });
        },
      );

      socket.once(
        "timeout",
        () => {
          finish({
            reachable:
              false,
            host,
            port,
            checkedAt,
            latencyMs:
              null,
            error:
              "Connection probe timed out.",
          });
        },
      );

      socket.once(
        "error",
        (error) => {
          finish({
            reachable:
              false,
            host,
            port,
            checkedAt,
            latencyMs:
              null,
            error:
              error.message,
          });
        },
      );
    },
  );
}
