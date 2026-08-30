import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  evaluateDataMigrationReadiness,
} from "../../../apps/api/src/services/dataMigrationReadiness";

describe("Milestone 25.3 database / persistent data migration readiness", () => {
  it("passes with reachable mysql and writable empty data directory",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    const result=
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "optional-store.json",
        ],
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });

  it("fails when mysql is unavailable",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    expect(
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          false,
        files:
          [],
      }).ready,
    ).toBe(
      false,
    );
  });

  it("fails when data dir is missing",()=> {
    expect(
      evaluateDataMigrationReadiness({
        dataDir:
          null,
        mysqlReachable:
          true,
        files:
          [],
      }).ready,
    ).toBe(
      false,
    );
  });

  it("allows absent optional store",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    const result=
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "missing.json",
        ],
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });

  it("fails invalid existing json store",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    fs.writeFileSync(
      path.join(
        dir,
        "bad.json",
      ),
      "{not-json",
      "utf8",
    );

    const result=
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "bad.json",
        ],
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("passes valid existing json store",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    fs.writeFileSync(
      path.join(
        dir,
        "good.json",
      ),
      JSON.stringify({
        version:
          1,
      }),
      "utf8",
    );

    expect(
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "good.json",
        ],
      }).ready,
    ).toBe(
      true,
    );
  });

  it("provides migration-readiness API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/data-migration-readiness"',
    );

    expect(route).toContain(
      "SELECT 1",
    );

    expect(route).toContain(
      "evaluateDataMigrationReadiness",
    );
  });
});
