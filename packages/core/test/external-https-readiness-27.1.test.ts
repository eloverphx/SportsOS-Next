import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateExternalHttpsReadiness,
} from "../../../apps/api/src/services/externalHttpsReadiness";

describe("Milestone 27.1 external HTTPS readiness", () => {
  it("passes a production HTTPS configuration",()=> {
    const result =
      evaluateExternalHttpsReadiness({
        NODE_ENV:
          "production",
        PUBLIC_API_URL:
          "https://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
        HOST:
          "0.0.0.0",
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );

    expect(
      result.expectations.tlsTermination,
    ).toBe(
      "external-reverse-proxy",
    );
  });

  it("rejects http public API",()=> {
    expect(
      evaluateExternalHttpsReadiness({
        NODE_ENV:
          "production",
        PUBLIC_API_URL:
          "http://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
        HOST:
          "0.0.0.0",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("rejects http dashboard origin",()=> {
    expect(
      evaluateExternalHttpsReadiness({
        NODE_ENV:
          "production",
        PUBLIC_API_URL:
          "https://api.example.com",
        DASHBOARD_ORIGIN:
          "http://sports.example.com",
        HOST:
          "0.0.0.0",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("documents forwarded proxy expectations",()=> {
    const result =
      evaluateExternalHttpsReadiness({
        NODE_ENV:
          "production",
        PUBLIC_API_URL:
          "https://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
        HOST:
          "0.0.0.0",
      });

    expect(
      result.expectations.forwardedProtoRequired,
    ).toBe(
      true,
    );

    expect(
      result.expectations.directContainerTlsRequired,
    ).toBe(
      false,
    );
  });
});
