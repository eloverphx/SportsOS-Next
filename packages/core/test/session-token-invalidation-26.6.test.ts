import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateSessionInvalidationReadiness,
} from "../../../apps/api/src/services/sessionInvalidationReadiness";

describe("Milestone 26.6 session / token invalidation readiness", () => {
  it("passes with strong production JWT configuration",()=> {
    const result=
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "abcdefghijklmnopqrstuvwxyz0123456789-strong",
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );

    expect(
      result.strategy,
    ).toBe(
      "jwt-secret-rotation",
    );
  });

  it("documents expected invalidation impact",()=> {
    const result=
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "abcdefghijklmnopqrstuvwxyz0123456789-strong",
      });

    expect(
      result.impact.activeJwtTokensInvalidated,
    ).toBe(
      true,
    );

    expect(
      result.impact.usersMustSignInAgain,
    ).toBe(
      true,
    );

    expect(
      result.impact.serverSessionStoreRequired,
    ).toBe(
      false,
    );
  });

  it("fails short JWT secret",()=> {
    expect(
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "too-short",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("fails non-production runtime",()=> {
    expect(
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "development",
        JWT_SECRET:
          "abcdefghijklmnopqrstuvwxyz0123456789-strong",
      }).ready,
    ).toBe(
      false,
    );
  });
});
