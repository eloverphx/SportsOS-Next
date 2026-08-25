import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  classifyStreamDestinationFailure,
} from "../../../apps/api/src/services/streamDestinationFailurePolicy";

describe("Milestone 24.6 stream destination failure handling", () => {
  it("classifies healthy destination",()=> {
    expect(
      classifyStreamDestinationFailure({
        ok:
          true,
      }).failureClass,
    ).toBe(
      "NONE",
    );
  });

  it("classifies auth failures as operator review",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          401,
      });

    expect(
      result.failureClass,
    ).toBe(
      "AUTHENTICATION",
    );

    expect(
      result.retryable,
    ).toBe(
      false,
    );
  });

  it("classifies rate limiting with backoff",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          429,
      });

    expect(
      result.failureClass,
    ).toBe(
      "RATE_LIMITED",
    );

    expect(
      result.action,
    ).toBe(
      "RETRY_WITH_BACKOFF",
    );
  });

  it("classifies server failures as retryable",()=> {
    expect(
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          503,
      }).retryable,
    ).toBe(
      true,
    );
  });

  it("classifies transient network failures",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        errorCode:
          "ECONNRESET",
      });

    expect(
      result.failureClass,
    ).toBe(
      "TRANSIENT_NETWORK",
    );

    expect(
      result.action,
    ).toBe(
      "RETRY_ALLOWED",
    );
  });

  it("classifies timeout separately",()=> {
    expect(
      classifyStreamDestinationFailure({
        ok:
          false,
        errorCode:
          "ETIMEDOUT",
      }).failureClass,
    ).toBe(
      "TIMEOUT",
    );
  });

  it("uses operator review for unknown failures",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        message:
          "something unusual",
      });

    expect(
      result.failureClass,
    ).toBe(
      "UNKNOWN",
    );

    expect(
      result.action,
    ).toBe(
      "OPERATOR_REVIEW",
    );
  });

  it("provides destination failure classification API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/destination-failure/classify"',
    );

    expect(route).toContain(
      "classifyStreamDestinationFailure",
    );
  });
});
