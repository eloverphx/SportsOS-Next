import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  validateSecretEnvironment,
} from "../../../apps/api/src/services/secretEnvironmentValidation";

describe("Milestone 25.4 secret / environment validation", () => {
  const goodEnv = {
    NODE_ENV:
      "production",
    JWT_SECRET:
      "this-is-a-real-jwt-key-with-32-plus-characters",
    MYSQL_PASSWORD:
      "mysql-prod-credential-123",
    MINIO_SECRET_KEY:
      "minio-prod-credential-123",
    DASHBOARD_ORIGIN:
      "http://192.168.5.3:4000",
    PUBLIC_API_URL:
      "http://192.168.5.3:4001",
    MYSQL_USER:
      "sportsos",
    MINIO_ACCESS_KEY:
      "sportsos",
  };

  it("passes strong production environment",()=> {
    expect(
      validateSecretEnvironment(
        goodEnv,
      ).ready,
    ).toBe(
      true,
    );
  });

  it("rejects development NODE_ENV",()=> {
    expect(
      validateSecretEnvironment({
        ...goodEnv,
        NODE_ENV:
          "development",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("rejects weak or placeholder JWT secret",()=> {
    const result=
      validateSecretEnvironment({
        ...goodEnv,
        JWT_SECRET:
          "replace-with-at-least-32-random-characters",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("rejects root mysql user",()=> {
    expect(
      validateSecretEnvironment({
        ...goodEnv,
        MYSQL_USER:
          "root",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("rejects malformed API URL",()=> {
    expect(
      validateSecretEnvironment({
        ...goodEnv,
        PUBLIC_API_URL:
          "not-a-url",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("does not expose secret values in check messages",()=> {
    const result=
      validateSecretEnvironment(
        goodEnv,
      );

    const serialized=
      JSON.stringify(
        result,
      );

    expect(
      serialized,
    ).not.toContain(
      goodEnv.JWT_SECRET,
    );

    expect(
      serialized,
    ).not.toContain(
      goodEnv.MYSQL_PASSWORD,
    );

    expect(
      serialized,
    ).not.toContain(
      goodEnv.MINIO_SECRET_KEY,
    );
  });

  it("provides secret-environment validation API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/secret-environment-validation"',
    );

    expect(route).toContain(
      "validateSecretEnvironment",
    );
  });
});
