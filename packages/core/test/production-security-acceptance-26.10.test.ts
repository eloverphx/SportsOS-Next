import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.10 production security acceptance", () => {
  const headers =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/plugins/securityHeaders.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const telemetry =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/securityTelemetry.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const audit =
    fs.readFileSync(
      new URL(
        "../../../scripts/secret-source-audit.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const regression =
    fs.readFileSync(
      new URL(
        "../../../scripts/security-regression-check.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const jwt =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-jwt-secret.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const mysql =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-mysql-password.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const minio =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-minio-credentials.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains transport/security header baseline",()=> {
    expect(headers).toContain(
      "x-content-type-options",
    );

    expect(headers).toContain(
      "x-frame-options",
    );

    expect(headers).toContain(
      "strict-transport-security",
    );

    expect(headers).toContain(
      "permissions-policy",
    );
  });

  it("retains consolidated operator security telemetry",()=> {
    expect(telemetry).toContain(
      "evaluateSecurityTelemetry",
    );

    expect(telemetry).toContain(
      "blockers",
    );
  });

  it("retains secret-source hardening",()=> {
    expect(audit).toContain(
      ".env permissions = 600",
    );

    expect(audit).toContain(
      ".env untracked",
    );
  });

  it("retains security regression runtime checks",()=> {
    expect(regression).toContain(
      "x-content-type-options:nosniff",
    );

    expect(regression).toContain(
      "x-frame-options:DENY",
    );

    expect(regression).toContain(
      "security telemetry rejects POST",
    );
  });

  it("retains safe credential rotation workflows",()=> {
    expect(jwt).toContain(
      "SPORTSOS_APPLY_ROTATION",
    );

    expect(mysql).toContain(
      "SPORTSOS_APPLY_ROTATION",
    );

    expect(minio).toContain(
      "SPORTSOS_APPLY_ROTATION",
    );
  });

  it("does not print generated credential values",()=> {
    expect(jwt).not.toContain(
      'echo "$NEW_SECRET"',
    );

    expect(mysql).not.toContain(
      'echo "$NEW_PASSWORD"',
    );

    expect(minio).not.toContain(
      'echo "$NEW_SECRET"',
    );
  });
});
