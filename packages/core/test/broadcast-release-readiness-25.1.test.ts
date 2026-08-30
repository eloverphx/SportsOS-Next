import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateBroadcastReleaseReadiness,
} from "../../../apps/api/src/services/broadcastReleaseReadiness";

describe("Milestone 25.1 runtime release readiness", () => {
  const good = {
    NODE_ENV:
      "production",
    PORT:
      "4001",
    HOST:
      "0.0.0.0",
    SPORTSOS_DATA_DIR:
      "/app/data",
    DASHBOARD_ORIGIN:
      "http://192.168.5.3:4000",
    PUBLIC_API_URL:
      "http://192.168.5.3:4001",
    MYSQL_HOST:
      "mysql",
    MYSQL_DATABASE:
      "sportsos",
    MYSQL_USER:
      "sportsos",
    MYSQL_PASSWORD:
      "configured",
    MINIO_ENDPOINT:
      "minio",
    MINIO_ACCESS_KEY:
      "sportsos",
    MINIO_SECRET_KEY:
      "configured",
    JWT_SECRET:
      "configured",
  };

  it("passes an actually configured production runtime",()=> {
    expect(
      evaluateBroadcastReleaseReadiness({
        env:
          good,
      }).ready,
    ).toBe(
      true,
    );
  });

  it("requires persistent /app/data",()=> {
    expect(
      evaluateBroadcastReleaseReadiness({
        env: {
          ...good,
          SPORTSOS_DATA_DIR:
            undefined,
        },
      }).ready,
    ).toBe(
      false,
    );
  });

  it("uses runtime env names from the API container",()=> {
    const result =
      evaluateBroadcastReleaseReadiness({
        env:
          good,
      });

    expect(
      result.checks.some(
        (check) =>
          check.id ===
            "runtime:dashboard-origin" &&
          check.ok,
      ),
    ).toBe(
      true,
    );

    expect(
      result.checks.some(
        (check) =>
          check.id ===
            "runtime:public-api-url" &&
          check.ok,
      ),
    ).toBe(
      true,
    );
  });

  it("does not require compose or Dockerfile source files at runtime",()=> {
    const result =
      evaluateBroadcastReleaseReadiness({
        env:
          good,
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });
});
