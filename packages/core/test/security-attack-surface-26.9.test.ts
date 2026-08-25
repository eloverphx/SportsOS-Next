import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  validateSecretEnvironment,
} from "../../../apps/api/src/services/secretEnvironmentValidation";

import {
  evaluateSessionInvalidationReadiness,
} from "../../../apps/api/src/services/sessionInvalidationReadiness";

describe("Milestone 26.9 security attack-surface regression", () => {
  it("rejects weak production credentials",()=> {
    const result =
      validateSecretEnvironment({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "short",
        MYSQL_PASSWORD:
          "short",
        MINIO_SECRET_KEY:
          "short",
        DASHBOARD_ORIGIN:
          "http://localhost:4000",
        PUBLIC_API_URL:
          "http://localhost:4001",
        MYSQL_USER:
          "sportsos",
        MINIO_ACCESS_KEY:
          "sportsos",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("requires production runtime for token invalidation readiness",()=> {
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

  it("keeps security dashboard read-only",()=> {
    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/security/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(page).not.toContain(
      'method: "POST"',
    );

    expect(page).not.toContain(
      'method: "PUT"',
    );

    expect(page).not.toContain(
      'method: "DELETE"',
    );
  });

  it("keeps deployment dashboard read-only",()=> {
    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/deployment/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(page).not.toContain(
      'method: "POST"',
    );

    expect(page).not.toContain(
      'method: "DELETE"',
    );
  });

  it("does not track .env in repository",()=> {
    const gitignore =
      fs.readFileSync(
        new URL(
          "../../../.gitignore",
          import.meta.url,
        ),
        "utf8",
      );

    expect(
      gitignore.includes(
        ".env",
      ),
    ).toBe(
      true,
    );
  });
});
