import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateResilienceRetryBudget,
} from "../../../apps/api/src/services/broadcastResilienceRetryBudget";

describe("Milestone 24.7 resilience retry budgets / backoff policy", () => {
  const retryableFailure = {
    failureClass:
      "TRANSIENT_NETWORK" as const,
    action:
      "RETRY_ALLOWED" as const,
    retryable:
      true,
    reason:
      "Transient network failure detected.",
  };

  it("schedules retry within budget",()=> {
    const now=100_000;

    const result=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        failure:
          retryableFailure,
        nowMs:
          now,
      });

    expect(
      result.state,
    ).toBe(
      "SCHEDULED",
    );

    expect(
      result.delayMs,
    ).toBe(
      5_000,
    );
  });

  it("uses exponential backoff",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          3,
        failure:
          retryableFailure,
      });

    expect(
      result.delayMs,
    ).toBe(
      40_000,
    );
  });

  it("caps delay",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          10,
        maxAttempts:
          20,
        failure:
          retryableFailure,
      });

    expect(
      result.delayMs,
    ).toBe(
      120_000,
    );
  });

  it("exhausts budget",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          5,
        failure:
          retryableFailure,
      });

    expect(
      result.state,
    ).toBe(
      "EXHAUSTED",
    );

    expect(
      result.retryAllowed,
    ).toBe(
      false,
    );
  });

  it("refuses operator-review failures",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        failure: {
          failureClass:
            "AUTHENTICATION",
          action:
            "OPERATOR_REVIEW",
          retryable:
            false,
          reason:
            "Authentication failed.",
        },
      });

    expect(
      result.state,
    ).toBe(
      "REFUSED",
    );
  });

  it("bounds configuration",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        maxAttempts:
          99,
        baseDelayMs:
          1,
        maxDelayMs:
          999_999,
        failure:
          retryableFailure,
      });

    expect(
      result.maxAttempts,
    ).toBe(
      20,
    );

    expect(
      result.delayMs,
    ).toBe(
      1_000,
    );
  });

  it("provides retry-budget API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/resilience-retry-budget"',
    );

    expect(route).toContain(
      "evaluateResilienceRetryBudget",
    );
  });
});
