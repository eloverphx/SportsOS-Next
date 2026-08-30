import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateTlsCertificateReadiness,
} from "../../../apps/api/src/services/tlsCertificateReadiness";

describe("Milestone 27.5 TLS certificate readiness", () => {
  it("accepts valid production HTTPS targets",()=> {
    const result =
      evaluateTlsCertificateReadiness({
        PUBLIC_API_URL:
          "https://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );

    expect(
      result.minimumDaysRemaining,
    ).toBe(
      14,
    );
  });

  it("deduplicates same TLS hostname",()=> {
    const result =
      evaluateTlsCertificateReadiness({
        PUBLIC_API_URL:
          "https://sports.example.com/api",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(
      result.targets,
    ).toEqual([
      "sports.example.com",
    ]);
  });

  it("rejects non-HTTPS targets",()=> {
    expect(
      evaluateTlsCertificateReadiness({
        PUBLIC_API_URL:
          "http://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("supports configurable expiry window",()=> {
    expect(
      evaluateTlsCertificateReadiness({
        PUBLIC_API_URL:
          "https://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
        SPORTSOS_TLS_MIN_DAYS:
          "30",
      }).minimumDaysRemaining,
    ).toBe(
      30,
    );
  });
});
