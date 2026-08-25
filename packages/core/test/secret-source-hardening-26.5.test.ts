import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.5 secret file / environment source hardening", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/secretSourceHardening.ts",
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

  it("requires restrictive env permissions",()=> {
    expect(service).toContain(
      '"600"',
    );
    expect(audit).toContain(
      "expected 600",
    );
  });

  it("requires env to be gitignored and untracked",()=> {
    expect(service).toContain(
      "env:gitignored",
    );
    expect(audit).toContain(
      "git check-ignore -q .env",
    );
    expect(audit).toContain(
      "git ls-files --error-unmatch .env",
    );
  });

  it("detects alternate environment sources",()=> {
    expect(service).toContain(
      ".env.local",
    );
    expect(service).toContain(
      ".env.production",
    );
    expect(service).toContain(
      ".env.development",
    );
    expect(service).toContain(
      ".env.override",
    );
  });

  it("audits secret duplication without printing values",()=> {
    expect(audit).toContain(
      "JWT_SECRET",
    );
    expect(audit).toContain(
      "MYSQL_PASSWORD",
    );
    expect(audit).toContain(
      "MINIO_ROOT_PASSWORD",
    );
    expect(audit).not.toContain(
      "cat .env",
    );
  });
});
