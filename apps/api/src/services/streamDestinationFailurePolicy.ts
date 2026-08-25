export type StreamDestinationFailureClass =
  | "NONE"
  | "TRANSIENT_NETWORK"
  | "AUTHENTICATION"
  | "CONFIGURATION"
  | "REMOTE_REJECTED"
  | "RATE_LIMITED"
  | "TIMEOUT"
  | "UNKNOWN";

export type StreamDestinationFailureAction =
  | "NONE"
  | "RETRY_ALLOWED"
  | "RETRY_WITH_BACKOFF"
  | "OPERATOR_REVIEW";

export type StreamDestinationFailureInput = {
  ok: boolean;
  statusCode?: number | null;
  errorCode?: string | null;
  message?: string | null;
};

export type StreamDestinationFailureDecision = {
  failureClass:
    StreamDestinationFailureClass;
  action:
    StreamDestinationFailureAction;
  retryable:
    boolean;
  reason:
    string;
};

export function classifyStreamDestinationFailure(
  input: StreamDestinationFailureInput,
): StreamDestinationFailureDecision {
  if (input.ok) {
    return {
      failureClass:
        "NONE",
      action:
        "NONE",
      retryable:
        false,
      reason:
        "Stream destination is healthy.",
    };
  }

  const status =
    input.statusCode ??
    null;

  const code =
    (input.errorCode ??
      "")
      .trim()
      .toUpperCase();

  const message =
    (input.message ??
      "")
      .trim()
      .toLowerCase();

  if (
    status === 401 ||
    status === 403 ||
    message.includes(
      "unauthorized",
    ) ||
    message.includes(
      "forbidden",
    ) ||
    message.includes(
      "authentication",
    )
  ) {
    return {
      failureClass:
        "AUTHENTICATION",
      action:
        "OPERATOR_REVIEW",
      retryable:
        false,
      reason:
        "Destination authentication or authorization failed.",
    };
  }

  if (
    status === 429 ||
    message.includes(
      "rate limit",
    )
  ) {
    return {
      failureClass:
        "RATE_LIMITED",
      action:
        "RETRY_WITH_BACKOFF",
      retryable:
        true,
      reason:
        "Destination is rate limiting publish traffic.",
    };
  }

  if (
    status !== null &&
    status >= 500 &&
    status <= 599
  ) {
    return {
      failureClass:
        "REMOTE_REJECTED",
      action:
        "RETRY_WITH_BACKOFF",
      retryable:
        true,
      reason:
        "Destination service returned a server-side failure.",
    };
  }

  if (
    status !== null &&
    status >= 400 &&
    status <= 499
  ) {
    return {
      failureClass:
        "CONFIGURATION",
      action:
        "OPERATOR_REVIEW",
      retryable:
        false,
      reason:
        "Destination rejected the request due to configuration or request data.",
    };
  }

  if (
    code ===
      "ETIMEDOUT" ||
    code ===
      "UND_ERR_CONNECT_TIMEOUT" ||
    message.includes(
      "timeout",
    ) ||
    message.includes(
      "timed out",
    )
  ) {
    return {
      failureClass:
        "TIMEOUT",
      action:
        "RETRY_WITH_BACKOFF",
      retryable:
        true,
      reason:
        "Destination connection timed out.",
    };
  }

  if (
    [
      "ECONNRESET",
      "ECONNREFUSED",
      "ENETUNREACH",
      "EHOSTUNREACH",
      "EAI_AGAIN",
    ].includes(
      code,
    ) ||
    message.includes(
      "connection reset",
    ) ||
    message.includes(
      "connection refused",
    ) ||
    message.includes(
      "network",
    )
  ) {
    return {
      failureClass:
        "TRANSIENT_NETWORK",
      action:
        "RETRY_ALLOWED",
      retryable:
        true,
      reason:
        "Transient network failure detected.",
    };
  }

  return {
    failureClass:
      "UNKNOWN",
    action:
      "OPERATOR_REVIEW",
    retryable:
      false,
    reason:
      "Destination failure could not be classified safely.",
  };
}
