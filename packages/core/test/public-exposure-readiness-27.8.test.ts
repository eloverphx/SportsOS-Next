import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluatePublicExposureReadiness,
} from "../../../apps/api/src/services/publicExposureReadiness";

describe("Milestone 27.8 public exposure readiness", () => {
  it("defines intended public surfaces",()=> {
    const result =
      evaluatePublicExposureReadiness({
        NODE_ENV:
          "production",
        PUBLIC_API_URL:
          "https://sports.example.com/api",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(
      result.intendedPublicPaths,
    ).toEqual([
      "/",
      "/api/",
      "/api/health",
      "/socket.io/",
    ]);
  });

  it("defines common blocked surfaces",()=> {
    const result =
      evaluatePublicExposureReadiness({
        NODE_ENV:
          "production",
        PUBLIC_API_URL:
          "https://sports.example.com/api",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(
      result.blockedPatterns,
    ).toContain(
      "/debug",
    );

    expect(
      result.blockedPatterns,
    ).toContain(
      "/swagger",
    );
  });

  it("requires production runtime",()=> {
    expect(
      evaluatePublicExposureReadiness({
        NODE_ENV:
          "development",
        PUBLIC_API_URL:
          "https://sports.example.com/api",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      }).ready,
    ).toBe(
      false,
    );
  });
});
