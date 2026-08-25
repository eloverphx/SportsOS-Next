import type {
  FastifyInstance,
} from "fastify";

const SECURITY_HEADERS = {
  "x-content-type-options":
    "nosniff",
  "x-frame-options":
    "DENY",
  "referrer-policy":
    "no-referrer",
  "cross-origin-opener-policy":
    "same-origin",
  "cross-origin-resource-policy":
    "same-origin",
  "permissions-policy":
    "camera=(), microphone=(), geolocation=()",
} as const;

export async function securityHeadersPlugin(
  app: FastifyInstance,
) {
  app.addHook(
    "onSend",
    async (
      _request,
      reply,
      payload,
    ) => {
      for (
        const [
          name,
          value,
        ]
        of Object.entries(
          SECURITY_HEADERS,
        )
      ) {
        if (
          name ===
          "x-frame-options"
        ) {
          reply.header(
            name,
            value,
          );

          continue;
        }

        if (
          !reply.hasHeader(
            name,
          )
        ) {
          reply.header(
            name,
            value,
          );
        }
      }

      if (
        process.env.NODE_ENV ===
        "production"
      ) {
        if (
          !reply.hasHeader(
            "strict-transport-security",
          )
        ) {
          reply.header(
            "strict-transport-security",
            "max-age=31536000; includeSubDomains",
          );
        }
      }

      return payload;
    },
  );
}
