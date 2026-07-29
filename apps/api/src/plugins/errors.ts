import type { FastifyError, FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

interface ErrorResponse {
  success: false;
  requestId: string;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

interface HttpError extends Error {
  readonly statusCode?: number;
  readonly code?: string;
}

function statusCodeFor(error: HttpError): number {
  if (
    typeof error.statusCode === "number" &&
    error.statusCode >= 400 &&
    error.statusCode <= 599
  ) {
    return error.statusCode;
  }

  return 500;
}

export async function registerErrorHandling(app: FastifyInstance): Promise<void> {
  app.setNotFoundHandler(
    async (request: FastifyRequest, reply: FastifyReply): Promise<ErrorResponse> => {
      reply.code(404);

      return {
        success: false,
        requestId: request.id,
        error: {
          code: "ROUTE_NOT_FOUND",
          message: `Route ${request.method} ${request.url} was not found`,
        },
      };
    },
  );

  app.setErrorHandler(
    async (
      error: FastifyError | HttpError,
      request: FastifyRequest,
      reply: FastifyReply,
    ): Promise<ErrorResponse> => {
      const statusCode = statusCodeFor(error);
      const isServerError = statusCode >= 500;

      if (isServerError) {
        request.log.error(
          {
            err: error,
            requestId: request.id,
          },
          "Request failed",
        );
      } else {
        request.log.warn(
          {
            err: error,
            requestId: request.id,
          },
          "Request rejected",
        );
      }

      reply.code(statusCode);

      return {
        success: false,
        requestId: request.id,
        error: {
          code: error.code ?? "INTERNAL_SERVER_ERROR",
          message: isServerError ? "An unexpected server error occurred" : error.message,
        },
      };
    },
  );
}
