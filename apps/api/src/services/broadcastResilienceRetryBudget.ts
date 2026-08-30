import {
  type StreamDestinationFailureDecision,
} from "./streamDestinationFailurePolicy.js";

export type ResilienceRetryBudgetState =
  | "AVAILABLE"
  | "SCHEDULED"
  | "EXHAUSTED"
  | "REFUSED";

export type ResilienceRetryBudgetInput = {
  attempts: number;
  maxAttempts?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  failure:
    StreamDestinationFailureDecision;
  nowMs?: number;
};

export type ResilienceRetryBudgetDecision = {
  state:
    ResilienceRetryBudgetState;
  retryAllowed:
    boolean;
  attempts:
    number;
  maxAttempts:
    number;
  delayMs:
    number | null;
  nextRetryAt:
    string | null;
  reason:
    string;
};

const DEFAULT_MAX_ATTEMPTS =
  5;

const DEFAULT_BASE_DELAY_MS =
  5_000;

const DEFAULT_MAX_DELAY_MS =
  120_000;

export function evaluateResilienceRetryBudget(
  input: ResilienceRetryBudgetInput,
): ResilienceRetryBudgetDecision {
  const attempts =
    Math.max(
      0,
      Math.floor(
        input.attempts,
      ),
    );

  const maxAttempts =
    Math.max(
      1,
      Math.min(
        Math.floor(
          input.maxAttempts ??
          DEFAULT_MAX_ATTEMPTS,
        ),
        20,
      ),
    );

  const baseDelayMs =
    Math.max(
      1_000,
      Math.min(
        Math.floor(
          input.baseDelayMs ??
          DEFAULT_BASE_DELAY_MS,
        ),
        60_000,
      ),
    );

  const maxDelayMs =
    Math.max(
      baseDelayMs,
      Math.min(
        Math.floor(
          input.maxDelayMs ??
          DEFAULT_MAX_DELAY_MS,
        ),
        600_000,
      ),
    );

  const nowMs =
    input.nowMs ??
    Date.now();

  if (
    !input.failure.retryable ||
    input.failure.action ===
      "OPERATOR_REVIEW"
  ) {
    return {
      state:
        "REFUSED",
      retryAllowed:
        false,
      attempts,
      maxAttempts,
      delayMs:
        null,
      nextRetryAt:
        null,
      reason:
        "Failure classification requires operator review.",
    };
  }

  if (
    attempts >=
    maxAttempts
  ) {
    return {
      state:
        "EXHAUSTED",
      retryAllowed:
        false,
      attempts,
      maxAttempts,
      delayMs:
        null,
      nextRetryAt:
        null,
      reason:
        "Resilience retry budget is exhausted.",
    };
  }

  const exponent =
    Math.max(
      0,
      attempts,
    );

  const delayMs =
    Math.min(
      maxDelayMs,
      baseDelayMs *
        2 ** exponent,
    );

  return {
    state:
      "SCHEDULED",
    retryAllowed:
      true,
    attempts,
    maxAttempts,
    delayMs,
    nextRetryAt:
      new Date(
        nowMs +
        delayMs,
      ).toISOString(),
    reason:
      input.failure.action ===
        "RETRY_WITH_BACKOFF"
        ? "Retry scheduled with exponential backoff."
        : "Retry scheduled within resilience retry budget.",
  };
}
