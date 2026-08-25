import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateCredentialRotationReadiness,
} from "../../../apps/api/src/services/credentialRotationReadiness";

describe("Milestone 26.1 credential rotation readiness", () => {
  const env = {
    JWT_SECRET:
      "configured-jwt",
    MYSQL_PASSWORD:
      "configured-mysql",
    MINIO_SECRET_KEY:
      "configured-minio",
    MYSQL_USER:
      "sportsos",
    MINIO_ACCESS_KEY:
      "sportsos",
    SPORTSOS_DATA_DIR:
      "/app/data",
  };

  it("passes when rollback, data, and current credentials are ready",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env,
        rollbackReady:
          true,
        dataMigrationReady:
          true,
      }).ready,
    ).toBe(
      true,
    );
  });

  it("requires rollback readiness",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env,
        rollbackReady:
          false,
        dataMigrationReady:
          true,
      }).ready,
    ).toBe(
      false,
    );
  });

  it("requires data migration readiness",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env,
        rollbackReady:
          true,
        dataMigrationReady:
          false,
      }).ready,
    ).toBe(
      false,
    );
  });

  it("requires all current rotation targets",()=> {
    const result=
      evaluateCredentialRotationReadiness({
        env: {
          ...env,
          JWT_SECRET:
            "",
        },
        rollbackReady:
          true,
        dataMigrationReady:
          true,
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );

    expect(
      result.targets,
    ).toEqual([
      "JWT_SECRET",
      "MYSQL_PASSWORD",
      "MINIO_SECRET_KEY",
    ]);
  });

  it("requires non-root mysql user",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env: {
          ...env,
          MYSQL_USER:
            "root",
        },
        rollbackReady:
          true,
        dataMigrationReady:
          true,
      }).ready,
    ).toBe(
      false,
    );
  });
});
