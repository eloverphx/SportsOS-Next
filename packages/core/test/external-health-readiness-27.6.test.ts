import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateExternalHealthReadiness,
} from "../../../apps/api/src/services/externalHealthReadiness";

describe("Milestone 27.6 external API/dashboard health readiness", () => {
  it("derives dashboard and API health targets",()=> {
    const result =
      evaluateExternalHealthReadiness({
        PUBLIC_API_URL:
          "https://sports.example.com/api",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );

    expect(
      result.targets,
    ).toEqual([
      {
        id:
          "dashboard",
        url:
          "https://sports.example.com/",
        required:
          true,
      },
      {
        id:
          "api-health",
        url:
          "https://sports.example.com/api/health",
        required:
          true,
      },
    ]);
  });

  it("supports separate API hostname",()=> {
    const result =
      evaluateExternalHealthReadiness({
        PUBLIC_API_URL:
          "https://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(
      result.targets.find(
        (target) =>
          target.id ===
          "api-health",
      )?.url,
    ).toBe(
      "https://api.example.com/api/health",
    );
  });

  it("rejects non-HTTPS external targets",()=> {
    expect(
      evaluateExternalHealthReadiness({
        PUBLIC_API_URL:
          "http://api.example.com",
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      }).ready,
    ).toBe(
      false,
    );
  });
});
